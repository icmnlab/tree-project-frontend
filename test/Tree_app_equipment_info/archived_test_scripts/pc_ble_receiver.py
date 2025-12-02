#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
電腦端 BLE 接收程式
模仿手機 APP 的邏輯，直接接收儀器數據並套用 v13.3 過濾器
"""

import asyncio
import re
from bleak import BleakScanner, BleakClient

# VLGEO2 儀器的 BLE 參數
SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"  # Nordic UART Service
TX_CHAR_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  # TX (接收數據)

# EOT 訊號
EOT_SIGNAL = bytes([0x5A, 0xBF, 0xFB])

# 全域變數
received_data = []
is_complete = False

def apply_v133_byte_filter(data_stream):
    """
    v13.3 完整 Byte-Level 過濾器
    
    三階段清理：
    1. 移除封包頭 + 回溯配對清理
    2. 全域配對雜訊清理（Non-ASCII + ASCII）
    3. 獨立 Non-ASCII 清理
    """
    
    # Stage 1: 封包頭 + 回溯
    cleaned_stage1 = []
    i = 0
    
    while i < len(data_stream):
        is_header = False
        if i + 2 < len(data_stream):
            if (data_stream[i] == 0x44 and data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00) or \
               (data_stream[i] == 0x44 and data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00):
                is_header = True
                
                # 回溯清理
                if len(cleaned_stage1) >= 2 and (cleaned_stage1[-1] > 0x7E or cleaned_stage1[-2] > 0x7E):
                    cleaned_stage1.pop()
                    cleaned_stage1.pop()
                elif len(cleaned_stage1) == 1 and cleaned_stage1[-1] > 0x7E:
                    cleaned_stage1.pop()
                
                i += 3
                continue
        
        cleaned_stage1.append(data_stream[i])
        i += 1
    
    # Stage 2: 全域配對清理
    cleaned_stage2 = []
    i = 0
    pair_removed = 0
    
    while i < len(cleaned_stage1):
        if i + 1 < len(cleaned_stage1):
            current_byte = cleaned_stage1[i]
            next_byte = cleaned_stage1[i+1]
            
            # Non-ASCII + ASCII 配對
            if current_byte > 0x7E and current_byte not in [0x0D, 0x0A]:
                if 0x20 <= next_byte <= 0x7E:
                    # 配對雜訊！兩個都移除
                    i += 2
                    pair_removed += 1
                    continue
                else:
                    # Non-ASCII 後不是 ASCII，只移除 Non-ASCII
                    i += 1
                    continue
        
        # 獨立的 Non-ASCII (保留換行符)
        if cleaned_stage1[i] > 0x7E and cleaned_stage1[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_stage2.append(cleaned_stage1[i])
        i += 1
    
    print(f"[Byte-Level Filter] 移除配對雜訊: {pair_removed} 對")
    
    return cleaned_stage2

def apply_v133_string_and_field_filter(decoded_text):
    """
    v13.3 String-Level + Field-Specific 過濾器
    """
    
    # String-Level 白名單
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # Structural Recovery + Field-Specific 清理
    recovered_lines = []
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        
        if len(line) <= 10:
            continue
        
        # 檢查是否以 $ 開頭
        if line.startswith('$'):
            recovered_lines.append(line)
            continue
        
        # v13.3: 智能結構匹配
        # 即使缺少 $，也嘗試辨識 VLGEO 數據模式
        if line.count(';') >= 20:
            fields = line.split(';')
            
            type_field = fields[2] if len(fields) > 2 else ''
            id_field = fields[6] if len(fields) > 6 else ''
            id_clean = re.sub(r'[^0-9]', '', id_field)
            
            # 檢查是否符合 VLGEO 數據模式
            is_valid_pattern = False
            
            # 條件 1: TYPE 欄位看起來合法
            if type_field in ['1P', '3P', '3D', 'DME', ''] or \
               any(vt in type_field for vt in ['1P', '3P', '3D', 'DME']):
                # 條件 2: ID 欄位是數字
                if id_clean and len(id_clean) >= 1:
                    is_valid_pattern = True
            
            if is_valid_pattern:
                # 補上 $
                recovered_line = '$' + line
                recovered_lines.append(recovered_line)
                print(f"[Structural Recovery] 恢復缺少 $ 的記錄: ID={id_clean}")
                continue
        
        # Header 或設定行
        if line.startswith('#'):
            recovered_lines.append(line)
    
    # Field-Specific 清理
    cleaned_lines = []
    
    for line in recovered_lines:
        if not line.startswith('$'):
            cleaned_lines.append(line)
            continue
        
        fields = line.split(';')
        
        # 清理數字欄位中的字母
        for idx in range(len(fields)):
            if idx not in [2, 13, 15, 32]:  # 保留 TYPE, N/S, E/W, UTM
                fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
            
            # TYPE 欄位修正
            if idx == 2:
                type_val = fields[idx]
                if type_val and type_val not in ['1P', '3P', '3D', 'DME', '']:
                    for valid_type in ['1P', '3P', '3D', 'DME']:
                        if valid_type in type_val:
                            fields[idx] = valid_type
                            break
        
        cleaned_lines.append(';'.join(fields))
    
    return cleaned_lines

def notification_handler(sender, data):
    """處理接收到的 BLE 數據"""
    global received_data, is_complete
    
    # 檢查 EOT 訊號
    if EOT_SIGNAL in data:
        print(f"\n[EOT] 偵測到結束訊號！")
        is_complete = True
        return
    
    # 儲存原始數據
    received_data.extend(list(data))
    
    # 顯示接收進度
    print(f"[BLE RX] 接收 {len(data)} bytes, 總計: {len(received_data)} bytes", end='\r')

async def scan_and_connect():
    """掃描並連接 VLGEO2 儀器"""
    print("=" * 80)
    print(" 掃描 Vertex Laser Geo 2 儀器...")
    print("=" * 80)
    print()
    
    devices = await BleakScanner.discover(timeout=10.0)
    
    vlgeo_device = None
    
    for device in devices:
        # 尋找名稱包含 "VLGEO" 或 "3190" 的裝置
        if device.name and ("VLGEO" in device.name or "3190" in device.name):
            vlgeo_device = device
            break
    
    if not vlgeo_device:
        print("未找到 VLGEO2 儀器！")
        print("\n可用裝置：")
        for device in devices:
            print(f"  {device.name} - {device.address}")
        return None
    
    print(f"找到儀器: {vlgeo_device.name} ({vlgeo_device.address})")
    print()
    
    return vlgeo_device

async def receive_data_from_device(device):
    """連接裝置並接收數據"""
    global received_data, is_complete
    
    print("=" * 80)
    print(" 連接並接收數據...")
    print("=" * 80)
    print()
    
    async with BleakClient(device.address) as client:
        print(f"[連接] 成功連接到 {device.name}")
        print()
        
        # 訂閱 TX Characteristic
        await client.start_notify(TX_CHAR_UUID, notification_handler)
        print(f"[訂閱] 已訂閱 TX Characteristic")
        print(f"[等待] 儀器傳輸數據...\n")
        
        # 等待傳輸完成（EOT 或超時）
        timeout = 120  # 2 分鐘超時
        elapsed = 0
        
        while not is_complete and elapsed < timeout:
            await asyncio.sleep(1)
            elapsed += 1
        
        # 停止訂閱
        await client.stop_notify(TX_CHAR_UUID)
        
        print(f"\n\n[完成] 接收 {len(received_data)} bytes")
        print()

async def main():
    """主程式"""
    global received_data
    
    print("\n")
    print("=" * 80)
    print(" PC BLE 接收程式 - 模仿手機 APP (v13.3)")
    print("=" * 80)
    print()
    
    # 1. 掃描裝置
    device = await scan_and_connect()
    
    if not device:
        print("\n請確保：")
        print("  1. 儀器已開機")
        print("  2. 電腦藍牙已啟用")
        print("  3. 儀器在藍牙範圍內")
        return
    
    # 2. 接收數據
    await receive_data_from_device(device)
    
    if not received_data:
        print("未接收到任何數據！")
        return
    
    # 3. 套用 v13.3 過濾器
    print("=" * 80)
    print(" 套用 v13.3 過濾器...")
    print("=" * 80)
    print()
    
    print("[Stage 1] Byte-Level 過濾...")
    cleaned_bytes = apply_v133_byte_filter(received_data)
    print(f"  原始: {len(received_data)} bytes")
    print(f"  清洗後: {len(cleaned_bytes)} bytes")
    print(f"  移除: {len(received_data) - len(cleaned_bytes)} bytes")
    print()
    
    # 解碼
    print("[Stage 2] 解碼...")
    try:
        decoded_text = bytes(cleaned_bytes).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_bytes).decode('latin-1', errors='ignore')
    
    print(f"  解碼: {len(decoded_text)} 字元")
    print()
    
    # String-Level + Field-Specific 過濾
    print("[Stage 3] String-Level + Field-Specific 過濾...")
    cleaned_lines = apply_v133_string_and_field_filter(decoded_text)
    
    # Last Record Wins
    id_records = {}
    for line in cleaned_lines:
        if not line.startswith('$'):
            continue
        
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                id_records[id_clean] = line
    
    print(f"  數據行: {len(cleaned_lines)} 筆")
    print(f"  唯一 ID: {len(id_records)} 個 (Last Record Wins)")
    print()
    
    # 4. 輸出 CSV
    output_file = 'PC_RECEIVED.CSV'
    
    print(f"[輸出] 儲存至 {output_file}...")
    
    # 加入 Header
    header = "MARK;STATUS;TYPE;PROD;VER;SNR;ID;UNIT;TRPH;REFH;P.OFF;DECL;LAT;N/S;LON;E/W;ALTITUDE;HDOP;DATE;UTC;SEQ;AREA;VOL;SD;HD;H;DIA;PITCH;AZ;X(m);Y(m);Z(m);UTM ZONE;\n"
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(header)
        
        # 按 ID 排序輸出
        for id_val in sorted(id_records.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            f.write(id_records[id_val] + '\n')
    
    print(f"  已儲存 {len(id_records)} 筆數據")
    print()
    
    # 5. 與官方 App 輸出比對
    print("=" * 80)
    print(" 與官方 App 輸出比對")
    print("=" * 80)
    print()
    
    official_file = 'DATA_2.CSV'
    
    official_records = {}
    with open(official_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    official_records[id_clean] = line
    
    print(f"官方 App: {len(official_records)} 個唯一 ID")
    print(f"我們接收: {len(id_records)} 個唯一 ID")
    print()
    
    # 比對
    matches = 0
    differences = []
    
    for id_val in sorted(official_records.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in id_records:
            if id_records[id_val] == official_records[id_val]:
                matches += 1
            else:
                differences.append(id_val)
        else:
            differences.append(f"{id_val} [MISSING]")
    
    total = len(official_records)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print(f"準確率: {matches}/{total} = {accuracy:.1f}%")
    print()
    
    if differences:
        print(f"差異/缺失: {len(differences)} 個")
        print(f"  {differences[:20]}")
        if len(differences) > 20:
            print(f"  ... 還有 {len(differences) - 20} 個")
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\n SUCCESS: 100% 成功！v13.3 完美運作！")
    elif accuracy >= 98:
        print(f"\n EXCELLENT: {accuracy:.1f}% - 非常接近完美！")
    elif accuracy >= 95:
        print(f"\n GREAT: {accuracy:.1f}% - 顯著成功！")
    elif accuracy >= 90:
        print(f"\n GOOD: {accuracy:.1f}% - 良好表現！")
    else:
        print(f"\n RESULT: {accuracy:.1f}%")
    
    print("=" * 80)
    print()

if __name__ == "__main__":
    print("\n使用說明：")
    print("  1. 確保電腦藍牙已啟用")
    print("  2. 開啟 VLGEO2 儀器")
    print("  3. 執行此程式")
    print("  4. 程式會自動掃描、連接、接收數據")
    print("  5. 接收完成後自動比對並輸出結果")
    print("\n按 Ctrl+C 可中斷...\n")
    
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n使用者中斷")
    except Exception as e:
        print(f"\n錯誤: {e}")
        print("\n如果出現 'bleak not found'，請執行: pip install bleak")

