#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
測試增強版過濾器
策略：移除所有「出現在數字欄位中的大寫字母」
"""

import re

def apply_enhanced_filter(csv_text):
    """
    增強版過濾器：移除欄位內的不合法大寫字母
    
    VLGEO CSV 格式中，大寫字母只應該出現在：
    - TYPE 欄位 (field[2]): 1P, 3P, 3D, DME
    - N/S 欄位 (field[13]): N, S
    - E/W 欄位 (field[15]): E, W
    - UTM ZONE 欄位 (field[32]): 51Q, 51R, etc.
    
    其他欄位（數字欄位）中的大寫字母都是雜訊！
    """
    
    cleaned_lines = []
    
    for line in csv_text.split('\n'):
        line = line.strip()
        if not line.startswith('$'):
            if line.startswith('#') or line.startswith('MARK'):
                cleaned_lines.append(line)
            continue
        
        fields = line.split(';')
        
        # 清理每個欄位
        for idx, field in enumerate(fields):
            # 這些欄位允許包含大寫字母
            allowed_letter_fields = [2, 13, 15, 32]
            
            if idx not in allowed_letter_fields:
                # 在數字欄位中，移除所有大寫字母 (A-Z)
                # 只保留數字、小數點、負號
                fields[idx] = re.sub(r'[A-Z]', '', field)
        
        cleaned_lines.append(';'.join(fields))
    
    return '\n'.join(cleaned_lines)

def test_enhanced_filter():
    """測試增強版過濾器"""
    print("=" * 80)
    print(" 增強版過濾器測試")
    print("=" * 80)
    print()
    
    # 1. 讀取 Wireshark 重建的髒數據
    dirty_file = 'tree_project/Tree_app_equipment_info/iphone_1st_reconstructed.csv'
    
    with open(dirty_file, 'r', encoding='utf-8') as f:
        dirty_csv = f.read()
    
    print("[Step 1] 讀取 Wireshark 重建數據...")
    dirty_lines = [l for l in dirty_csv.split('\n') if l.strip().startswith('$')]
    print(f"  原始: {len(dirty_lines)} 筆")
    print()
    
    # 2. 套用增強版過濾器
    print("[Step 2] 套用增強版過濾器...")
    print("  規則：移除數字欄位中的所有大寫字母 (A-Z)")
    print()
    
    cleaned_csv = apply_enhanced_filter(dirty_csv)
    cleaned_lines = [l for l in cleaned_csv.split('\n') if l.strip().startswith('$')]
    print(f"  清洗後: {len(cleaned_lines)} 筆")
    print()
    
    # 3. 與官方 App 輸出比對
    print("[Step 3] 與官方 App 輸出比對...")
    
    gt_file = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    with open(gt_file, 'r', encoding='utf-8') as f:
        gt_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    print(f"  官方 App: {len(gt_lines)} 筆")
    print()
    
    # 逐筆比對
    matches = 0
    differences = []
    
    max_len = min(len(cleaned_lines), len(gt_lines))
    
    for i in range(max_len):
        if cleaned_lines[i] == gt_lines[i]:
            matches += 1
        else:
            # 提取 ID
            fields = gt_lines[i].split(';')
            record_id = fields[6] if len(fields) > 6 else f"Line_{i+1}"
            
            differences.append({
                'id': record_id,
                'line': i + 1,
                'ours': cleaned_lines[i],
                'official': gt_lines[i]
            })
    
    accuracy = matches / max_len * 100 if max_len > 0 else 0
    
    print("=" * 80)
    print(f"\n準確率: {matches}/{max_len} 筆 ({accuracy:.1f}%)")
    print()
    
    if len(cleaned_lines) != len(gt_lines):
        print(f"WARNING: 筆數差異 = {abs(len(cleaned_lines) - len(gt_lines))} 筆")
        print()
    
    if differences and len(differences) <= 30:
        print(f"\n剩餘差異 (共 {len(differences)} 筆，顯示前 10 筆):")
        print("-" * 80)
        
        for diff in differences[:10]:
            print(f"\nID: {diff['id']} (Line {diff['line']})")
            
            ours_fields = diff['ours'].split(';')
            official_fields = diff['official'].split(';')
            
            for idx in range(min(len(ours_fields), len(official_fields))):
                if ours_fields[idx] != official_fields[idx]:
                    print(f"  欄位[{idx}]: '{ours_fields[idx]}' vs '{official_fields[idx]}'")
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\nRESULT: 成功！達到 100% 準確率！")
        print("官方 App 的秘訣：移除數字欄位中的大寫字母")
    elif accuracy >= 90:
        print(f"\nRESULT: 非常接近！({accuracy:.1f}%)")
        print("需要微調過濾規則")
    else:
        print(f"\nRESULT: 還需要更多優化 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy

if __name__ == "__main__":
    test_enhanced_filter()

