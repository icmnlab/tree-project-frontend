#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
測試我們 Android App 的過濾器效果
從 ble_debug_log.txt 重建 CSV，並與官方 Android App 輸出比對
"""

import re

def extract_from_android_log(log_file):
    """從 Android BLE Log 提取並重建 CSV（使用 v13.1 過濾器）"""
    
    # 1. 提取 [BLE RAW] fragments
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    print(f"[BLE RAW] fragments: {len(raw_fragments)}")
    
    # 2. 重組 byte stream
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    print(f"Raw byte stream: {len(full_byte_stream)} bytes")
    
    # 3. 套用 v13.1 Byte-Level 過濾器
    cleaned_data = []
    i = 0
    removed = 0
    
    while i < len(full_byte_stream):
        # 偵測封包頭
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                
                # 回溯清理
                if len(cleaned_data) >= 2 and (cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E):
                    cleaned_data.pop()
                    cleaned_data.pop()
                    removed += 2
                elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                    cleaned_data.pop()
                    removed += 1
                
                removed += 3
                i += 3
                continue
        
        # 過濾獨立 Non-ASCII
        if full_byte_stream[i] > 0x7E and full_byte_stream[i] not in [0x0D, 0x0A]:
            removed += 1
            i += 1
            continue
        
        cleaned_data.append(full_byte_stream[i])
        i += 1
    
    print(f"After Byte-Level filter: {len(cleaned_data)} bytes (removed {removed})")
    
    # 4. 解碼
    try:
        decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    print(f"Decoded: {len(decoded_text)} chars")
    
    # 5. String-Level 白名單過濾
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    print(f"After String-Level filter: {len(cleaned_text)} chars")
    
    # 6. 提取數據行
    data_lines = []
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if line.startswith('$') and len(line) > 10:  # 排除太短的行
            data_lines.append(line)
    
    print(f"Data lines: {len(data_lines)}")
    
    return data_lines

def compare_with_official_android():
    """與官方 Android App 輸出比對"""
    print("=" * 80)
    print(" 我們的 Android App (v13.1) vs 官方 Android Haglof Link")
    print("=" * 80)
    print()
    
    # 1. 從我們的 Log 重建
    print("[Step 1] 從我們的 ble_debug_log.txt 重建...")
    ble_log = 'tree_project/project_code/frontend/ble_debug_log.txt'
    
    try:
        our_lines = extract_from_android_log(ble_log)
    except Exception as e:
        print(f"ERROR: {e}")
        return
    
    print()
    
    # 2. 讀取官方 Android App 輸出
    print("[Step 2] 讀取官方 Android App 輸出...")
    gt_file = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    with open(gt_file, 'r', encoding='utf-8') as f:
        official_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    print(f"  官方 Android: {len(official_lines)} 筆")
    print()
    
    # 3. 比對（使用 Last Record Wins）
    print("[Step 3] 比對（Last Record Wins）...")
    
    # 建立 ID mapping
    our_by_id = {}
    for line in our_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_str = fields[6].strip()
            id_clean = re.sub(r'[^0-9]', '', id_str)
            if id_clean:
                our_by_id[id_clean] = line  # Last wins
    
    official_by_id = {}
    for line in official_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_str = fields[6].strip()
            id_clean = re.sub(r'[^0-9]', '', id_str)
            if id_clean:
                official_by_id[id_clean] = line  # Last wins
    
    print(f"  我們的 App (唯一 ID): {len(our_by_id)} 個")
    print(f"  官方 App (唯一 ID): {len(official_by_id)} 個")
    print()
    
    # 比對
    matches = 0
    differences = []
    
    for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in our_by_id:
            if our_by_id[id_val] == official_by_id[id_val]:
                matches += 1
            else:
                differences.append({
                    'id': id_val,
                    'ours': our_by_id[id_val][:120],
                    'official': official_by_id[id_val][:120]
                })
    
    total = len(official_by_id)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print("=" * 80)
    print(f"\n準確率: {matches}/{total} 個唯一 ID ({accuracy:.1f}%)")
    print()
    
    if differences:
        print(f"\n差異列表 (共 {len(differences)} 筆，顯示前 15 筆):")
        print("-" * 80)
        
        for diff in differences[:15]:
            print(f"\nID: {diff['id']}")
            
            # 找出欄位差異
            ours_fields = diff['ours'].split(';')
            official_fields = diff['official'].split(';')
            
            diff_count = 0
            for idx in range(min(len(ours_fields), len(official_fields))):
                if ours_fields[idx] != official_fields[idx] and diff_count < 3:
                    print(f"  欄位[{idx}]: '{ours_fields[idx]}' vs '{official_fields[idx]}'")
                    diff_count += 1
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\nRESULT: 成功！我們達到官方 App 的水準！可以發布！")
    elif accuracy >= 95:
        print(f"\nRESULT: 非常接近 ({accuracy:.1f}%)，微調後可發布")
    elif accuracy >= 90:
        print(f"\nRESULT: 接近目標 ({accuracy:.1f}%)，還需優化")
    elif accuracy >= 80:
        print(f"\nRESULT: 還有一段距離 ({accuracy:.1f}%)，需要找出剩餘問題")
    else:
        print(f"\nRESULT: 需要重大改進 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy

if __name__ == "__main__":
    compare_with_official_android()






