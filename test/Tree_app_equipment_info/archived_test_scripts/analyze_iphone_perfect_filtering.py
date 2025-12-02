#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
從 iPhone Wireshark 抓包分析官方 App 的完美過濾策略
"""

import re

def extract_att_payloads_from_wireshark(filepath):
    """從 Wireshark 文本提取 ATT Notification payload"""
    payloads = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到所有 ATT Handle Value Notification 的 Frame
    frames = re.findall(
        r'Rcvd Handle Value Notification.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n((?:0000.*?\n)+)',
        content,
        re.DOTALL
    )
    
    all_bytes = []
    
    for frame in frames:
        # 解析 hex dump
        hex_lines = frame.strip().split('\n')
        for hex_line in hex_lines:
            # 格式: "0000  03 4b 20 1b 00 17 00 04 00 1b 13 00 PAYLOAD..."
            # 移除前面的 offset
            hex_line = re.sub(r'^[0-9a-fA-F]+\s+', '', hex_line)
            
            # 分割成 hex bytes
            hex_parts = hex_line.split()
            
            for hex_str in hex_parts:
                if len(hex_str) == 2:
                    try:
                        byte_val = int(hex_str, 16)
                        all_bytes.append(byte_val)
                    except ValueError:
                        pass
    
    # 移除 BLE/L2CAP Header (前 12 bytes)
    # 格式: 03 4b 20 XX XX XX XX 04 00 1b 13 00 [Payload]
    #       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ (12 bytes header)
    
    clean_payloads = []
    i = 0
    while i < len(all_bytes):
        # 尋找 ATT Notification 的特徵: 1b 13 00 在 offset 9-11
        if i + 12 < len(all_bytes):
            if all_bytes[i] == 0x03 and all_bytes[i+1] == 0x4b:
                # 這是一個 BLE 封包的開始
                # 找到長度
                length = all_bytes[i+3]  # L2CAP length (包含 4 bytes L2CAP header)
                
                # Payload 從 offset 12 開始
                payload_start = i + 12
                payload_length = length - 4  # 減去 L2CAP header
                
                if payload_start + payload_length <= len(all_bytes):
                    payload = all_bytes[payload_start:payload_start + payload_length]
                    clean_payloads.extend(payload)
                    i = payload_start + payload_length
                else:
                    i += 1
            else:
                i += 1
        else:
            i += 1
    
    return clean_payloads

def simple_extract_all_hex_after_header(filepath):
    """簡單方法：提取所有 ATT 封包中 header 之後的 payload"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到所有包含 "Rcvd Handle Value Notification" 的 Frame
    # 然後提取後續的 hex dump
    pattern = r'Rcvd Handle Value Notification.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n.*?\n((?:0000.*?\n)+)'
    
    matches = re.findall(pattern, content, re.DOTALL)
    
    all_bytes = []
    
    for match in matches:
        # 解析每個 frame 的 hex dump
        lines = match.strip().split('\n')
        
        for line in lines:
            # 移除 offset
            line = re.sub(r'^[0-9a-fA-F]+\s+', '', line)
            
            # 提取 hex bytes (前面部分，ASCII部分在後面)
            hex_part = line.split('  ')[0] if '  ' in line else line
            
            hex_bytes = hex_part.split()
            
            for hex_str in hex_bytes:
                if len(hex_str) == 2:
                    try:
                        byte_val = int(hex_str, 16)
                        all_bytes.append(byte_val)
                    except ValueError:
                        pass
        
        # 移除每個 frame 的前 12 bytes (BLE/L2CAP header)
        # ATT payload 從第 13 個 byte 開始
        if len(all_bytes) >= 12:
            pass  # 先保留完整，稍後統一處理
    
    # 統一移除 header
    cleaned = []
    i = 0
    frame_count = 0
    
    while i < len(all_bytes):
        # 檢測 frame 開始: 03 4b 20
        if i + 12 < len(all_bytes) and all_bytes[i] == 0x03 and all_bytes[i+1] == 0x4b and all_bytes[i+2] == 0x20:
            # 跳過 12 bytes header
            i += 12
            frame_count += 1
            
            # 讀取 payload (最多 20 bytes，因為 BLE MTU)
            payload_len = 0
            while payload_len < 20 and i < len(all_bytes):
                # 檢查是否遇到下一個 frame
                if i + 2 < len(all_bytes) and all_bytes[i] == 0x03 and all_bytes[i+1] == 0x4b and all_bytes[i+2] == 0x20:
                    break
                cleaned.append(all_bytes[i])
                i += 1
                payload_len += 1
        else:
            i += 1
    
    return cleaned, frame_count

def reconstruct_csv_from_iphone(iphone_file1, iphone_file2, ground_truth_file):
    """從 iPhone 抓包重建 CSV 並與官方 App 比對"""
    print("=" * 80)
    print(" iPhone Wireshark 抓包分析 - 尋找 100% 復原的秘訣")
    print("=" * 80)
    print()
    
    # 1. 提取兩次測試的 payload
    print("[Step 1] 提取 iPhone Wireshark ATT Payloads...")
    
    payloads1, frames1 = simple_extract_all_hex_after_header(iphone_file1)
    print(f"  第1次測試: {len(payloads1)} bytes (來自 {frames1} 個 frames)")
    
    payloads2, frames2 = simple_extract_all_hex_after_header(iphone_file2)
    print(f"  第2次測試: {len(payloads2)} bytes (來自 {frames2} 個 frames)")
    print()
    
    # 使用有數據的測試結果
    data_stream = payloads2 if len(payloads2) > len(payloads1) else payloads1
    
    # 2. 解碼並查看原始數據
    print("[Step 2] 解碼原始數據...")
    try:
        raw_text = bytes(data_stream).decode('utf-8', errors='ignore')
    except:
        raw_text = bytes(data_stream).decode('latin-1', errors='ignore')
    
    print(f"  原始文本長度: {len(raw_text)} 字元")
    print()
    print("  前 500 字元:")
    print("-" * 80)
    print(raw_text[:500])
    print("-" * 80)
    print()
    
    # 3. 套用我們的 v13.1 過濾器
    print("[Step 3] 套用 v13.1 Byte-Level 過濾器...")
    
    cleaned_data = []
    i = 0
    removed_count = 0
    
    while i < len(data_stream):
        # 偵測封包頭
        is_header = False
        if i + 2 < len(data_stream):
            if (data_stream[i] == 0x44 and data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00) or \
               (data_stream[i] == 0x44 and data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00):
                is_header = True
                
                # 回溯清理
                if len(cleaned_data) >= 2 and (cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E):
                    cleaned_data.pop()
                    cleaned_data.pop()
                    removed_count += 2
                elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                    cleaned_data.pop()
                    removed_count += 1
                
                removed_count += 3
                i += 3
                continue
        
        # 過濾獨立 Non-ASCII
        if data_stream[i] > 0x7E and data_stream[i] not in [0x0D, 0x0A]:
            removed_count += 1
            i += 1
            continue
        
        cleaned_data.append(data_stream[i])
        i += 1
    
    print(f"  清洗後: {len(cleaned_data)} bytes")
    if len(data_stream) > 0:
        print(f"  移除雜訊: {removed_count} bytes ({removed_count/len(data_stream)*100:.1f}%)")
    else:
        print(f"  移除雜訊: {removed_count} bytes")
    print()
    
    # 4. 解碼並套用 String-Level 白名單
    print("[Step 4] 解碼並套用 String-Level 白名單...")
    try:
        decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # String-Level 白名單：只保留 VLGEO 合法字元
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    print(f"  白名單過濾後: {len(cleaned_text)} 字元")
    print()
    
    # 5. 提取數據行
    print("[Step 5] 提取數據行...")
    data_lines = []
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if line.startswith('$'):
            data_lines.append(line)
    
    print(f"  重建數據: {len(data_lines)} 筆")
    print()
    
    # 6. 讀取官方 App 輸出
    print("[Step 6] 讀取官方 App 輸出 (Ground Truth)...")
    gt_lines = []
    with open(ground_truth_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('$'):
                gt_lines.append(line)
    
    print(f"  官方 App: {len(gt_lines)} 筆")
    print()
    
    # 7. 比對
    print("[Step 7] 詳細比對...")
    print("=" * 80)
    
    matches = 0
    differences = []
    
    max_len = min(len(data_lines), len(gt_lines))
    
    for i in range(max_len):
        if data_lines[i] == gt_lines[i]:
            matches += 1
        else:
            # 提取 ID
            id_match = re.search(r';;;;(\d+);', gt_lines[i])
            record_id = id_match.group(1) if id_match else f"Line_{i+1}"
            
            differences.append({
                'id': record_id,
                'line': i + 1,
                'ours': data_lines[i],
                'official': gt_lines[i]
            })
    
    accuracy = matches / max_len * 100 if max_len > 0 else 0
    
    print(f"\n準確率: {matches}/{max_len} 筆 ({accuracy:.1f}%)")
    print()
    
    if len(data_lines) != len(gt_lines):
        print(f"WARNING: 筆數不一致")
        print(f"  我們重建: {len(data_lines)} 筆")
        print(f"  官方 App: {len(gt_lines)} 筆")
        print()
    
    if differences:
        print(f"\n差異列表 (共 {len(differences)} 筆，顯示前 10 筆):")
        print("-" * 80)
        
        for diff in differences[:10]:
            print(f"\nID: {diff['id']} (Line {diff['line']})")
            
            # 找出具體差異
            ours_fields = diff['ours'].split(';')
            official_fields = diff['official'].split(';')
            
            for idx, (f1, f2) in enumerate(zip(ours_fields, official_fields)):
                if f1 != f2:
                    print(f"  欄位[{idx}]: '{f1}' vs '{f2}'")
    
    print()
    print("=" * 80)
    
    if accuracy >= 100:
        print("\nSTATUS: 完美！達到 100% 準確率！")
    elif accuracy >= 99:
        print("\nSTATUS: 非常接近！幾乎完美！")
    elif accuracy >= 90:
        print(f"\nSTATUS: 接近成功 ({accuracy:.1f}%)，需要微調")
    else:
        print(f"\nSTATUS: 需要進一步優化 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy, differences

if __name__ == "__main__":
    iphone_file1 = 'tree_project/Tree_app_equipment_info/比對用/1st_full(101-2637).txt'
    iphone_file2 = 'tree_project/Tree_app_equipment_info/比對用/2nd_full(90-2626).txt'
    ground_truth = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    
    accuracy, diffs = reconstruct_csv_from_iphone(iphone_file1, iphone_file2, ground_truth)

