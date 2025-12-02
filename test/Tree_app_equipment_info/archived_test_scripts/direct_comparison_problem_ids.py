#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
直接比對有問題的幾個 ID
顯示完整的欄位，找出具體哪裡不同
"""

import re

def extract_and_filter_v132(log_file):
    """v13.2 過濾器"""
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
    
    # 重組
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    # Byte-Level 過濾
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
    
    # String-Level
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # Field-Specific + Last Record Wins
    id_records = {}
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if not line.startswith('$') or len(line) <= 10:
            continue
        
        fields = line.split(';')
        
        # 清理
        for idx in range(len(fields)):
            if idx not in [2, 13, 15, 32]:
                fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
            
            if idx == 2:
                type_val = fields[idx]
                if type_val and type_val not in ['1P', '3P', '3D', 'DME', '']:
                    for valid_type in ['1P', '3P', '3D', 'DME']:
                        if valid_type in type_val:
                            fields[idx] = valid_type
                            break
        
        cleaned_line = ';'.join(fields)
        
        id_clean = re.sub(r'[^0-9]', '', fields[6]) if len(fields) > 6 else ''
        if id_clean:
            id_records[id_clean] = cleaned_line  # Last wins
    
    return id_records

# 執行比對
print("=" * 80)
print(" 直接比對問題 ID 的完整記錄")
print("=" * 80)
print()

our_records = extract_and_filter_v132('tree_project/project_code/frontend/ble_debug_log.txt')

official_records = {}
with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line.startswith('$'):
            continue
        
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                official_records[id_clean] = line

# 檢查幾個關鍵 ID
problem_ids = ['10031', '10034', '10042', '10071', '10087', '10092']

for pid in problem_ids:
    print(f"\n### ID: {pid}")
    
    if pid in our_records:
        ours_line = our_records[pid]
        official_line = official_records.get(pid, '')
        
        if ours_line == official_line:
            print("  完全匹配！")
        else:
            ours_fields = ours_line.split(';')
            official_fields = official_line.split(';')
            
            print(f"  欄位數: 我們={len(ours_fields)}, 官方={len(official_fields)}")
            print()
            
            # 只顯示有差異的欄位
            for idx in range(max(len(ours_fields), len(official_fields))):
                ours_val = ours_fields[idx] if idx < len(ours_fields) else '[缺失]'
                official_val = official_fields[idx] if idx < len(official_fields) else '[缺失]'
                
                if ours_val != official_val:
                    print(f"  欄位[{idx}]: '{ours_val}' vs '{official_val}'")
    else:
        print(f"  我們的數據中找不到此 ID！")
    
    print("-" * 80)

print("\n" + "=" * 80)

