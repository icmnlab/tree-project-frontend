#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
深入分析最後的 21 筆差異
找出數字異常的規律
"""

import re

def extract_and_filter(log_file):
    """從 Log 重建並套用 v13.2 過濾器"""
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
    
    # 重組 byte stream
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    # v13.1 Byte-Level 過濾器
    cleaned_data = []
    i = 0
    
    while i < len(full_byte_stream):
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                
                if len(cleaned_data) >= 2 and (cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E):
                    cleaned_data.pop()
                    cleaned_data.pop()
                elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                    cleaned_data.pop()
                
                i += 3
                continue
        
        if full_byte_stream[i] > 0x7E and full_byte_stream[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_data.append(full_byte_stream[i])
        i += 1
    
    # 解碼
    try:
        decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # String-Level 白名單
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # 提取數據行
    data_lines = []
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if line.startswith('$') and len(line) > 10:
            data_lines.append(line)
    
    # 套用 Field-Specific 過濾
    cleaned_lines = []
    for line in data_lines:
        fields = line.split(';')
        
        for idx in range(len(fields)):
            # 移除數字欄位中的大寫字母
            if idx not in [2, 13, 15, 32]:
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

def analyze_final_errors():
    """深入分析最後的差異"""
    print("=" * 80)
    print(" 分析最後 6.2% 的差異 - 找出數字異常規律")
    print("=" * 80)
    print()
    
    # 1. 重建
    our_lines = extract_and_filter('tree_project/project_code/frontend/ble_debug_log.txt')
    
    our_by_id = {}
    for line in our_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                our_by_id[id_clean] = line
    
    # 2. 讀取官方輸出
    with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
        official_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    official_by_id = {}
    for line in official_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                official_by_id[id_clean] = line
    
    # 3. 找出所有差異
    differences = []
    for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in our_by_id and our_by_id[id_val] != official_by_id[id_val]:
            differences.append({
                'id': id_val,
                'ours': our_by_id[id_val],
                'official': official_by_id[id_val]
            })
    
    print(f"剩餘差異: {len(differences)} 筆")
    print()
    
    # 4. 詳細分析每一筆
    print("=" * 80)
    print(" 詳細分析每筆差異")
    print("=" * 80)
    
    for i, diff in enumerate(differences, 1):
        print(f"\n### 案例 {i}: ID={diff['id']}")
        print()
        
        ours_fields = diff['ours'].split(';')
        official_fields = diff['official'].split(';')
        
        # 顯示所有欄位差異
        field_diffs = []
        for idx in range(max(len(ours_fields), len(official_fields))):
            ours_val = ours_fields[idx] if idx < len(ours_fields) else ''
            official_val = official_fields[idx] if idx < len(official_fields) else ''
            
            if ours_val != official_val:
                field_diffs.append({
                    'idx': idx,
                    'ours': ours_val,
                    'official': official_val
                })
        
        # 顯示差異
        for fd in field_diffs[:5]:
            print(f"  欄位[{fd['idx']}]:")
            print(f"    我們:   '{fd['ours']}'")
            print(f"    官方:   '{fd['official']}'")
            
            # 分析差異類型
            if fd['ours'] and fd['official']:
                # 檢查是否為數字重複
                if fd['ours'].replace('.', '').replace('-', '').isdigit() and \
                   fd['official'].replace('.', '').replace('-', '').isdigit():
                    
                    ours_digits = fd['ours'].replace('.', '').replace('-', '')
                    official_digits = fd['official'].replace('.', '').replace('-', '')
                    
                    # 檢查是否為數字重複
                    if len(ours_digits) > len(official_digits):
                        # 檢查是否包含重複模式
                        if official_digits in ours_digits:
                            extra = ours_digits.replace(official_digits, '', 1)
                            print(f"      → 數字重複？額外: '{extra}'")
                        else:
                            print(f"      → 數字完全不同")
                    elif len(ours_digits) == len(official_digits):
                        print(f"      → 長度相同但值不同")
                    else:
                        print(f"      → 我們缺少數字")
        
        if len(field_diffs) > 5:
            print(f"  ... 還有 {len(field_diffs) - 5} 個欄位差異")
        
        print("-" * 80)
        
        if i >= 15:
            print(f"\n... 還有 {len(differences) - 15} 筆未顯示")
            break
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    analyze_final_errors()






