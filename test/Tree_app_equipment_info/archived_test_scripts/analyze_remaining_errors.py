#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
深度分析剩餘的 16.1% 差異
找出官方 App 的額外過濾規則
"""

import re
from collections import defaultdict

def extract_from_android_log(log_file):
    """從 Android BLE Log 重建（v13.1 過濾器）"""
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
    
    return data_lines

def analyze_error_patterns():
    """深度分析錯誤模式"""
    print("=" * 80)
    print(" 深度錯誤模式分析 - 找出官方 App 的額外過濾規則")
    print("=" * 80)
    print()
    
    # 1. 重建我們的數據
    print("[Step 1] 從 ble_debug_log.txt 重建...")
    our_lines = extract_from_android_log('tree_project/project_code/frontend/ble_debug_log.txt')
    print(f"  我們: {len(our_lines)} 筆")
    
    # 2. 讀取官方輸出
    with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
        official_lines = [l.strip() for l in f if l.strip().startswith('$')]
    print(f"  官方: {len(official_lines)} 筆")
    print()
    
    # 3. Last Record Wins
    our_by_id = {}
    for line in our_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                our_by_id[id_clean] = line
    
    official_by_id = {}
    for line in official_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                official_by_id[id_clean] = line
    
    # 4. 找出所有差異並分類
    print("[Step 2] 分析差異模式...")
    print()
    
    error_types = defaultdict(list)
    
    for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val not in our_by_id:
            continue
        
        if our_by_id[id_val] == official_by_id[id_val]:
            continue
        
        # 有差異，分析具體模式
        ours_fields = our_by_id[id_val].split(';')
        official_fields = official_by_id[id_val].split(';')
        
        for idx in range(min(len(ours_fields), len(official_fields))):
            if ours_fields[idx] != official_fields[idx]:
                ours_val = ours_fields[idx]
                official_val = official_fields[idx]
                
                # 分類錯誤類型
                error_type = 'Unknown'
                
                # 類型 1：我們多了字母
                extra_letters = re.findall(r'[A-Z]', ours_val)
                official_letters = re.findall(r'[A-Z]', official_val)
                if len(extra_letters) > len(official_letters):
                    error_type = 'Extra_Letters'
                    error_types[error_type].append({
                        'id': id_val,
                        'field': idx,
                        'ours': ours_val,
                        'official': official_val,
                        'extra': set(extra_letters) - set(official_letters)
                    })
                    continue
                
                # 類型 2：數字位數不同（可能是額外數字）
                ours_digits = re.sub(r'[^0-9]', '', ours_val)
                official_digits = re.sub(r'[^0-9]', '', official_val)
                if len(ours_digits) > len(official_digits):
                    error_type = 'Extra_Digits'
                    error_types[error_type].append({
                        'id': id_val,
                        'field': idx,
                        'ours': ours_val,
                        'official': official_val
                    })
                    continue
                
                # 類型 3：我們有值，官方是空的
                if ours_val and not official_val:
                    error_type = 'Should_Be_Empty'
                    error_types[error_type].append({
                        'id': id_val,
                        'field': idx,
                        'ours': ours_val,
                        'official': official_val
                    })
                    continue
                
                # 類型 4：數字完全不同
                error_type = 'Different_Number'
                error_types[error_type].append({
                    'id': id_val,
                    'field': idx,
                    'ours': ours_val,
                    'official': official_val
                })
    
    # 5. 輸出分類結果
    print("=" * 80)
    print(" 錯誤類型統計")
    print("=" * 80)
    print()
    
    for error_type, errors in sorted(error_types.items(), key=lambda x: len(x[1]), reverse=True):
        print(f"\n[{error_type}] 共 {len(errors)} 個")
        print("-" * 80)
        
        for i, err in enumerate(errors[:8], 1):
            print(f"{i}. ID={err['id']}, 欄位[{err['field']}]:")
            print(f"   我們:   '{err['ours']}'")
            print(f"   官方:   '{err['official']}'")
            
            if 'extra' in err:
                print(f"   多餘字母: {err['extra']}")
        
        if len(errors) > 8:
            print(f"   ... 還有 {len(errors) - 8} 個案例")
    
    print()
    print("=" * 80)
    
    # 6. 推斷過濾規則
    print("\n[推斷官方 App 的額外過濾規則]")
    print("-" * 80)
    print()
    
    if 'Extra_Letters' in error_types:
        all_extra_letters = set()
        for err in error_types['Extra_Letters']:
            if 'extra' in err:
                all_extra_letters.update(err['extra'])
        
        print(f"1. 移除數字欄位中的大寫字母:")
        print(f"   發現的雜訊字母: {sorted(all_extra_letters)}")
        print(f"   → 規則：在 TYPE, N/S, E/W, UTM 以外的欄位，移除所有 A-Z")
        print()
    
    if 'Extra_Digits' in error_types:
        print(f"2. 智能數字修正 (共 {len(error_types['Extra_Digits'])} 個案例)")
        print(f"   可能有特殊的數字驗證邏輯")
        print()
    
    if 'Different_Number' in error_types:
        print(f"3. 數字完全不同 (共 {len(error_types['Different_Number'])} 個案例)")
        print(f"   可能是重複傳輸選擇了不同版本")
        print()
    
    print("=" * 80)

if __name__ == "__main__":
    analyze_error_patterns()

