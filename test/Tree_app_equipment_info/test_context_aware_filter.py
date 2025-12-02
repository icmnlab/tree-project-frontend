#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
測試 Context-Aware 過濾器
在數字欄位中移除所有 A-Z 字母
"""

import re

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

def apply_context_aware_filter(data_lines):
    """
    套用 Context-Aware 過濾器
    在數字欄位中移除所有 A-Z 字母
    """
    # 允許包含字母的欄位索引
    LETTER_ALLOWED_FIELDS = [2, 13, 15, 32]  # TYPE, N/S, E/W, UTM ZONE
    
    cleaned_lines = []
    
    for line in data_lines:
        fields = line.split(';')
        
        # 清理每個欄位
        for idx in range(len(fields)):
            if idx not in LETTER_ALLOWED_FIELDS:
                # 在數字欄位中，移除所有大寫字母
                # 只保留數字、小數點、負號、$、#
                fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
        
        cleaned_lines.append(';'.join(fields))
    
    return cleaned_lines

def test_context_aware_filter():
    """測試 Context-Aware 過濾器"""
    print("=" * 80)
    print(" 測試 Context-Aware 過濾器 (v13.2 候選)")
    print("=" * 80)
    print()
    
    # 1. 從我們的 Log 重建
    print("[Step 1] 從 ble_debug_log.txt 重建 (v13.1 過濾器)...")
    our_lines = extract_from_android_log('tree_project/project_code/frontend/ble_debug_log.txt')
    print(f"  v13.1 重建: {len(our_lines)} 筆")
    print()
    
    # 2. 套用 Context-Aware 過濾
    print("[Step 2] 套用 Context-Aware 過濾器...")
    print("  規則：在 TYPE, N/S, E/W, UTM 以外的欄位，移除所有 A-Z")
    print()
    
    enhanced_lines = apply_context_aware_filter(our_lines)
    print(f"  增強後: {len(enhanced_lines)} 筆")
    print()
    
    # 3. Last Record Wins
    our_by_id = {}
    for line in enhanced_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                our_by_id[id_clean] = line
    
    # 4. 讀取官方輸出
    print("[Step 3] 讀取官方 Android App 輸出...")
    with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
        official_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    official_by_id = {}
    for line in official_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                official_by_id[id_clean] = line
    
    print(f"  官方 Android: {len(official_by_id)} 個唯一 ID")
    print()
    
    # 5. 比對
    print("[Step 4] 比對結果...")
    print("=" * 80)
    
    matches = 0
    differences = []
    
    for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in our_by_id:
            if our_by_id[id_val] == official_by_id[id_val]:
                matches += 1
            else:
                differences.append({
                    'id': id_val,
                    'ours': our_by_id[id_val],
                    'official': official_by_id[id_val]
                })
    
    total = len(official_by_id)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print(f"\n準確率: {matches}/{total} 個唯一 ID ({accuracy:.1f}%)")
    print(f"改善: {accuracy - 83.9:.1f}% (從 83.9% 提升)")
    print()
    
    if differences:
        print(f"\n剩餘差異 (共 {len(differences)} 筆，顯示前 10 筆):")
        print("-" * 80)
        
        for diff in differences[:10]:
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
        print("\nRESULT: 100% 成功！可以發布！")
        print("官方 App 的秘訣就是：Context-Aware Letter Filtering")
    elif accuracy >= 95:
        print(f"\nRESULT: 非常接近 ({accuracy:.1f}%)！")
        print("Context-Aware 過濾有效，還需要處理數字異常")
    elif accuracy >= 90:
        print(f"\nRESULT: 顯著改善 ({accuracy:.1f}%)！")
        print("Context-Aware 過濾器是正確方向")
    elif accuracy > 83.9:
        print(f"\nRESULT: 有改善 ({accuracy:.1f}%)，但不夠")
    else:
        print(f"\nRESULT: 無改善 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy, differences

if __name__ == "__main__":
    test_context_aware_filter()

