#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查 v13.2 剩餘的 11 筆差異
"""

import re

# 從 test_global_pair_removal.py 複製相同的過濾邏輯
def apply_v132_filter(log_file):
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
    
    # 兩階段清理
    # Stage 1: 封包頭 + 回溯
    cleaned_stage1 = []
    i = 0
    
    while i < len(full_byte_stream):
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                
                if len(cleaned_stage1) >= 2 and (cleaned_stage1[-1] > 0x7E or cleaned_stage1[-2] > 0x7E):
                    cleaned_stage1.pop()
                    cleaned_stage1.pop()
                elif len(cleaned_stage1) == 1 and cleaned_stage1[-1] > 0x7E:
                    cleaned_stage1.pop()
                
                i += 3
                continue
        
        cleaned_stage1.append(full_byte_stream[i])
        i += 1
    
    # Stage 2: 全域配對清理
    cleaned_stage2 = []
    i = 0
    
    while i < len(cleaned_stage1):
        if i + 1 < len(cleaned_stage1):
            current_byte = cleaned_stage1[i]
            next_byte = cleaned_stage1[i+1]
            
            if current_byte > 0x7E and current_byte not in [0x0D, 0x0A]:
                if 0x20 <= next_byte <= 0x7E:
                    # 配對雜訊，兩個都移除
                    i += 2
                    continue
                else:
                    i += 1
                    continue
        
        if cleaned_stage1[i] > 0x7E and cleaned_stage1[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_stage2.append(cleaned_stage1[i])
        i += 1
    
    # 解碼
    try:
        decoded_text = bytes(cleaned_stage2).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_stage2).decode('latin-1', errors='ignore')
    
    # String-Level
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # Field-Specific + Last Record Wins
    id_records = {}
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if not line.startswith('$') or len(line) <= 10:
            continue
        
        fields = line.split(';')
        
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
            id_records[id_clean] = cleaned_line
    
    return id_records

# 檢查關鍵 ID
print("檢查關鍵修正效果：")
print("=" * 80)

our_records = apply_v132_filter('tree_project/project_code/frontend/ble_debug_log.txt')

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

# 檢查之前有問題的 ID
test_ids = ['10031', '10034', '10042', '10024']

for test_id in test_ids:
    if test_id in our_records and test_id in official_records:
        ours = our_records[test_id]
        official = official_records[test_id]
        
        if ours == official:
            print(f"\nID {test_id}: FIXED!")
        else:
            ours_fields = ours.split(';')
            official_fields = official.split(';')
            
            print(f"\nID {test_id}: Still different")
            for idx in range(min(len(ours_fields), len(official_fields))):
                if ours_fields[idx] != official_fields[idx]:
                    print(f"  field[{idx}]: '{ours_fields[idx]}' vs '{official_fields[idx]}'")
                    break

print("\n" + "=" * 80)






