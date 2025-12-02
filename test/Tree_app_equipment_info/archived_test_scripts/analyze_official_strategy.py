#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析原廠 APP 的 BLE 過濾策略

目標：找出原廠 APP 如何達到 100%，而非靠硬編碼特殊案例

分析方法：
1. 從 BLE log JSON 提取原始封包
2. 觀察 iPhone 官方 APP 的輸出 (DATA_from_iphone.CSV)
3. 比對我們的處理結果
4. 找出原廠的通用過濾規則
"""

import json
import re
import os

# 問題 ID 列表（目前需要硬編碼修正的）
PROBLEM_IDS = ['10071', '10087', '10092']

def extract_att_value_from_packet(packet):
    """從封包中提取 ATT value (實際數據)"""
    try:
        layers = packet.get('_source', {}).get('layers', {})
        btatt = layers.get('btatt', {})
        
        # 取得 value_raw - 這是實際的 BLE 數據
        value_raw = btatt.get('btatt.value_raw', [])
        if value_raw and len(value_raw) > 0:
            hex_str = value_raw[0]
            # 轉換 hex 為 bytes 再轉為 ASCII
            try:
                data_bytes = bytes.fromhex(hex_str)
                return data_bytes, hex_str
            except:
                pass
        return None, None
    except:
        return None, None

def analyze_ble_log_for_problem_ids(json_files, problem_ids):
    """分析 BLE log 中問題 ID 的原始封包"""
    
    print("="*80)
    print(" 分析問題 ID 的原始 BLE 封包")
    print("="*80)
    
    all_packets_data = []
    
    for json_file in json_files:
        if not os.path.exists(json_file):
            continue
        
        print(f"\n讀取: {os.path.basename(json_file)}")
        
        with open(json_file, 'r', encoding='utf-8') as f:
            packets = json.load(f)
        
        for packet in packets:
            data_bytes, hex_str = extract_att_value_from_packet(packet)
            if data_bytes:
                # 嘗試解碼為 ASCII
                try:
                    ascii_str = data_bytes.decode('ascii', errors='replace')
                    all_packets_data.append({
                        'hex': hex_str,
                        'bytes': data_bytes,
                        'ascii': ascii_str,
                        'frame_num': packet.get('_source', {}).get('layers', {}).get('frame', {}).get('frame.number', '?')
                    })
                except:
                    pass
    
    print(f"\n總共提取 {len(all_packets_data)} 個 ATT 封包")
    
    # 搜尋問題 ID 相關的封包
    print("\n" + "-"*80)
    print(" 搜尋問題 ID 相關封包")
    print("-"*80)
    
    for problem_id in problem_ids:
        print(f"\n### ID={problem_id} ###")
        
        found_packets = []
        for pkt in all_packets_data:
            # 搜尋包含此 ID 的封包
            if problem_id in pkt['ascii'] or f";{problem_id};" in pkt['ascii']:
                found_packets.append(pkt)
        
        if found_packets:
            print(f"找到 {len(found_packets)} 個相關封包:")
            for i, pkt in enumerate(found_packets[:5], 1):
                print(f"\n  [{i}] Frame #{pkt['frame_num']}")
                print(f"      Hex: {pkt['hex'][:60]}...")
                print(f"      ASCII: {pkt['ascii'][:80]}...")
        else:
            print("  未找到直接相關封包")

def compare_official_vs_ours():
    """比較原廠 APP 輸出與我們的處理結果"""
    
    print("\n" + "="*80)
    print(" 比較原廠 APP vs 我們的結果")
    print("="*80)
    
    base_dir = os.path.dirname(__file__)
    
    # 讀取 iPhone 官方輸出
    iphone_csv = os.path.join(base_dir, 'DATA_from_iphone.CSV')
    official_by_id = {}
    
    with open(iphone_csv, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    official_by_id[id_clean] = {
                        'line': line,
                        'fields': fields
                    }
    
    # 讀取我們的處理結果 (無硬編碼版本)
    our_csv = os.path.join(base_dir, 'PC_RECEIVED_V135.CSV')  # v135 是無硬編碼版本
    our_by_id = {}
    
    if os.path.exists(our_csv):
        with open(our_csv, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line.startswith('$'):
                    continue
                fields = line.split(';')
                if len(fields) > 6:
                    id_clean = re.sub(r'[^0-9]', '', fields[6])
                    if id_clean:
                        our_by_id[id_clean] = {
                            'line': line,
                            'fields': fields
                        }
    
    # 分析問題 ID
    print("\n問題 ID 詳細分析:")
    print("-"*80)
    
    for problem_id in PROBLEM_IDS:
        print(f"\n### ID={problem_id} ###")
        
        if problem_id in official_by_id:
            off = official_by_id[problem_id]
            print(f"\n  [原廠 iPhone APP]:")
            
            # 顯示關鍵欄位
            if len(off['fields']) > 19:
                print(f"    UTC [19]: '{off['fields'][19]}'")
            if len(off['fields']) > 14:
                print(f"    LON [14]: '{off['fields'][14]}'")
            if len(off['fields']) > 24:
                print(f"    HD [24]: '{off['fields'][24]}'")
        
        if problem_id in our_by_id:
            our = our_by_id[problem_id]
            print(f"\n  [我們的處理 (無硬編碼)]:")
            
            if len(our['fields']) > 19:
                print(f"    UTC [19]: '{our['fields'][19]}'")
            if len(our['fields']) > 14:
                print(f"    LON [14]: '{our['fields'][14]}'")
            if len(our['fields']) > 24:
                print(f"    HD [24]: '{our['fields'][24]}'")
        
        # 找出差異
        if problem_id in official_by_id and problem_id in our_by_id:
            off_fields = official_by_id[problem_id]['fields']
            our_fields = our_by_id[problem_id]['fields']
            
            print(f"\n  [差異欄位]:")
            for idx in range(min(len(off_fields), len(our_fields))):
                if off_fields[idx] != our_fields[idx]:
                    print(f"    欄位[{idx}]: 原廠='{off_fields[idx]}' | 我們='{our_fields[idx]}'")

def analyze_pattern_for_100_percent():
    """分析達到 100% 的通用規則"""
    
    print("\n" + "="*80)
    print(" 尋找通用過濾規則")
    print("="*80)
    
    base_dir = os.path.dirname(__file__)
    
    # 讀取所有 PC_RECEIVED 版本來追蹤演化
    versions = [
        ('PC_RECEIVED.CSV', 'v13.1 基礎版'),
        ('PC_RECEIVED_V134.CSV', 'v13.4 Context-Aware'),
        ('PC_RECEIVED_V135.CSV', 'v13.5 Field-Specific'),
        ('PC_RECEIVED_V135_PLUS.CSV', 'v13.5+ 含硬編碼')
    ]
    
    official_csv = os.path.join(base_dir, 'DATA_2.CSV')
    
    # 讀取官方資料
    official_by_id = {}
    with open(official_csv, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    official_by_id[id_clean] = line
    
    print(f"\n官方資料: {len(official_by_id)} 筆")
    
    for version_file, version_name in versions:
        filepath = os.path.join(base_dir, version_file)
        if not os.path.exists(filepath):
            continue
        
        our_by_id = {}
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line.startswith('$'):
                    continue
                fields = line.split(';')
                if len(fields) > 6:
                    id_clean = re.sub(r'[^0-9]', '', fields[6])
                    if id_clean:
                        our_by_id[id_clean] = line
        
        # 計算準確率
        matches = sum(1 for id_val in official_by_id if id_val in our_by_id and our_by_id[id_val] == official_by_id[id_val])
        accuracy = matches / len(official_by_id) * 100
        
        # 找出錯誤
        errors = []
        for id_val in official_by_id:
            if id_val in our_by_id and our_by_id[id_val] != official_by_id[id_val]:
                errors.append(id_val)
        
        print(f"\n{version_name}:")
        print(f"  準確率: {accuracy:.2f}% ({matches}/{len(official_by_id)})")
        print(f"  錯誤 ID: {errors[:10]}...")

def main():
    base_dir = os.path.dirname(__file__)
    
    # 1. 比較原廠 vs 我們
    compare_official_vs_ours()
    
    # 2. 分析版本演化
    analyze_pattern_for_100_percent()
    
    # 3. 分析 BLE 原始封包
    json_files = [
        os.path.join(base_dir, '(0-1000)ble_log.json'),
        os.path.join(base_dir, '(1001-2000)ble_log.json'),
        os.path.join(base_dir, '(2001-2665)ble_log.json')
    ]
    
    # 只分析問題 ID（這個會很慢）
    # analyze_ble_log_for_problem_ids(json_files, PROBLEM_IDS)
    
    print("\n" + "="*80)
    print(" 結論")
    print("="*80)
    print("""
關鍵問題：3 個 ID 的錯誤來源
- ID=10071: HD 欄位 '42.5' 應為 '4.5'
- ID=10087: UTC 欄位 '855089' 應為 '85508'  
- ID=10092: LON 欄位 '120.53664472' 應為 '120.5366472'

這些錯誤都是 BLE 傳輸中插入的雜訊導致：
- PacketLogger 封包頭 (44 CD 00) 前後的雜訊 bytes
- 這些 bytes 恰好是數字的 ASCII 碼，混入了資料中

原廠 APP 可能的策略：
1. 更嚴格的 Byte-Level 過濾（在更早階段移除雜訊）
2. 使用 CRC/Checksum 驗證封包完整性
3. 基於 VLGEO 規格的欄位範圍驗證
4. 重傳機制（丟棄錯誤封包，等待重傳）

建議下一步：
1. 檢查 BLE log JSON 中問題 ID 的原始 Hex 序列
2. 分析雜訊插入的確切位置
3. 設計更通用的過濾規則
""")

if __name__ == "__main__":
    main()
