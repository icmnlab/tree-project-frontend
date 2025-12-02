#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
測試 v13.2 Global Pair Removal 過濾器
全域清理所有「Non-ASCII + ASCII」配對雜訊
"""

import re

def apply_v132_global_pair_filter(data_stream):
    """
    v13.2 全域配對清理過濾器
    
    策略：兩階段清理
    1. 第一階段：移除封包頭及其前的配對雜訊（保留原邏輯）
    2. 第二階段：移除所有剩餘的「Non-ASCII + ASCII」配對
    """
    
    # === 第一階段：封包頭 + 回溯配對清理 ===
    cleaned_stage1 = []
    i = 0
    
    while i < len(data_stream):
        # 偵測封包頭
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
        
        # 保留所有 bytes (包括 Non-ASCII，稍後處理)
        cleaned_stage1.append(data_stream[i])
        i += 1
    
    # === 第二階段：全域配對雜訊清理 ===
    cleaned_stage2 = []
    i = 0
    removed_pairs = 0
    
    while i < len(cleaned_stage1):
        # 檢測「Non-ASCII + ASCII」配對
        if i + 1 < len(cleaned_stage1):
            current_byte = cleaned_stage1[i]
            next_byte = cleaned_stage1[i+1]
            
            # 如果當前是 Non-ASCII（且不是換行符），檢查下一個
            if current_byte > 0x7E and current_byte not in [0x0D, 0x0A]:
                # 如果下一個是 ASCII 可見字元（0x20-0x7E）
                if 0x20 <= next_byte <= 0x7E:
                    # 這是配對雜訊，兩個都移除！
                    i += 2
                    removed_pairs += 1
                    continue
                else:
                    # Non-ASCII 後面不是 ASCII，只移除 Non-ASCII
                    i += 1
                    continue
        
        # 獨立的 Non-ASCII (保留換行符)
        if cleaned_stage1[i] > 0x7E and cleaned_stage1[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        # 保留正常 byte
        cleaned_stage2.append(cleaned_stage1[i])
        i += 1
    
    return cleaned_stage2, removed_pairs

def test_v132_filter():
    """測試 v13.2 過濾器"""
    print("=" * 80)
    print(" 測試 v13.2 Global Pair Removal 過濾器")
    print("=" * 80)
    print()
    
    # 1. 讀取 Log
    print("[Step 1] 讀取 ble_debug_log.txt...")
    
    with open('tree_project/project_code/frontend/ble_debug_log.txt', 'r', encoding='utf-16') as f:
        content = f.read()
    
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    print(f"  BLE fragments: {len(raw_fragments)}")
    
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
    
    print(f"  Raw byte stream: {len(full_byte_stream)} bytes")
    print()
    
    # 2. 套用 v13.2 過濾器
    print("[Step 2] 套用 v13.2 Global Pair Removal 過濾器...")
    
    cleaned_data, removed_pairs = apply_v132_global_pair_filter(full_byte_stream)
    
    print(f"  清洗後: {len(cleaned_data)} bytes")
    print(f"  移除雜訊: {len(full_byte_stream) - len(cleaned_data)} bytes")
    print(f"  其中配對雜訊: {removed_pairs} 對 ({removed_pairs * 2} bytes)")
    print()
    
    # 3. 解碼
    print("[Step 3] 解碼並套用 String-Level + Field-Specific 過濾...")
    
    try:
        decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # String-Level 白名單
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    print(f"  白名單過濾後: {len(cleaned_text)} chars")
    print()
    
    # 4. Field-Specific 過濾 + Last Record Wins
    print("[Step 4] Field-Specific 過濾 + Last Record Wins...")
    
    id_records = {}
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if not line.startswith('$') or len(line) <= 10:
            continue
        
        fields = line.split(';')
        
        # Field-Specific 清理
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
    
    print(f"  最終記錄: {len(id_records)} 個唯一 ID")
    print()
    
    # 5. 與官方比對
    print("[Step 5] 與官方 Android App 輸出比對...")
    
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
    
    print(f"  官方: {len(official_records)} 個唯一 ID")
    print()
    
    # 比對
    matches = 0
    differences = []
    
    for id_val in sorted(official_records.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in id_records:
            if id_records[id_val] == official_records[id_val]:
                matches += 1
            else:
                differences.append({
                    'id': id_val,
                    'ours': id_records[id_val],
                    'official': official_records[id_val]
                })
    
    total = len(official_records)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print("=" * 80)
    print(f"\n準確率: {matches}/{total} 個唯一 ID ({accuracy:.1f}%)")
    print(f"改善: +{accuracy - 93.8:.1f}% (從 v13.1 的 93.8% 提升)")
    print()
    
    if differences:
        print(f"\n剩餘差異 (共 {len(differences)} 筆):")
        print("-" * 80)
        
        for diff in differences[:10]:
            print(f"\nID: {diff['id']}")
            
            ours_fields = diff['ours'].split(';')
            official_fields = diff['official'].split(';')
            
            diff_count = 0
            for idx in range(min(len(ours_fields), len(official_fields))):
                if ours_fields[idx] != official_fields[idx] and diff_count < 3:
                    print(f"  欄位[{idx}]: '{ours_fields[idx]}' vs '{official_fields[idx]}'")
                    diff_count += 1
        
        if len(differences) > 10:
            print(f"\n... 還有 {len(differences) - 10} 筆")
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\n SUCCESS: 100% 成功！可以發布！")
        print("v13.2 Global Pair Removal 過濾器有效！")
    elif accuracy >= 98:
        print(f"\n EXCELLENT: 非常接近 100% ({accuracy:.1f}%)！")
        print("v13.2 是正確方向，還有少數 edge cases")
    elif accuracy >= 95:
        print(f"\n GREAT: 顯著改善 ({accuracy:.1f}%)！")
        print("Global Pair Removal 有效")
    elif accuracy > 93.8:
        print(f"\n GOOD: 有改善 ({accuracy:.1f}%)！")
    else:
        print(f"\n NEUTRAL: 無明顯改善 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy

if __name__ == "__main__":
    test_v132_filter()

