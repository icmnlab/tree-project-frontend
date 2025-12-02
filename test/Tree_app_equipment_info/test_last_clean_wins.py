#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
測試「Last Clean Record Wins」假設
對每個 ID，選擇「最乾淨」的記錄（最少雜訊字母的那筆）
"""

import re

def count_noise_in_line(line):
    """計算一行中的雜訊字母數量"""
    # 提取數字欄位（排除 TYPE, N/S, E/W, UTM ZONE）
    fields = line.split(';')
    
    # 允許字母的欄位
    allowed_fields = [2, 13, 15, 32]  # TYPE, N/S, E/W, UTM ZONE
    
    noise_count = 0
    
    for idx, field in enumerate(fields):
        if idx in allowed_fields:
            continue
        
        # 在數字欄位中，大寫字母視為雜訊
        noise_letters = re.findall(r'[A-Z]', field)
        noise_count += len(noise_letters)
    
    return noise_count

def apply_last_clean_wins(csv_lines):
    """
    對每個 ID，選擇最乾淨的記錄
    如果有多筆同 ID，選雜訊最少的那筆；若雜訊相同，選最後一筆
    """
    # 建立 ID -> records 的映射
    id_records = {}
    
    for line in csv_lines:
        fields = line.split(';')
        if len(fields) <= 6:
            continue
        
        id_raw = fields[6].strip()
        id_clean = re.sub(r'[^0-9]', '', id_raw)
        
        if not id_clean:
            continue
        
        noise_count = count_noise_in_line(line)
        
        if id_clean not in id_records:
            id_records[id_clean] = []
        
        id_records[id_clean].append({
            'line': line,
            'noise': noise_count,
            'index': len(id_records[id_clean])  # 記錄順序
        })
    
    # 對每個 ID，選擇最乾淨的記錄
    selected_lines = []
    
    for id_val, records in sorted(id_records.items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0):
        # 按雜訊數量排序，雜訊最少的在前；雜訊相同則保留最後一筆（index 最大的）
        records.sort(key=lambda r: (r['noise'], -r['index']))
        
        selected = records[0]  # 選雜訊最少的
        selected_lines.append(selected['line'])
        
        if len(records) > 1:
            print(f"ID {id_val}: {len(records)} 筆記錄，雜訊範圍 {[r['noise'] for r in records]}, 選擇雜訊={selected['noise']}")
    
    return selected_lines

def test_strategy():
    """測試策略"""
    print("=" * 80)
    print(" 測試「Last Clean Record Wins」策略")
    print("=" * 80)
    print()
    
    # 1. 讀取 Wireshark 重建數據
    dirty_file = 'tree_project/Tree_app_equipment_info/iphone_1st_reconstructed.csv'
    
    with open(dirty_file, 'r', encoding='utf-8') as f:
        dirty_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    print(f"[Step 1] Wireshark 重建數據: {len(dirty_lines)} 筆")
    print()
    
    # 2. 套用「選擇最乾淨記錄」策略
    print(f"[Step 2] 套用「Last Clean Record Wins」策略...")
    print()
    
    selected_lines = apply_last_clean_wins(dirty_lines)
    
    print()
    print(f"  選擇後: {len(selected_lines)} 筆")
    print()
    
    # 3. 與官方 App 輸出比對
    print(f"[Step 3] 與官方 App 輸出比對...")
    
    gt_file = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    with open(gt_file, 'r', encoding='utf-8') as f:
        gt_lines = [l.strip() for l in f if l.strip().startswith('$')]
    
    print(f"  官方 App: {len(gt_lines)} 筆")
    print()
    
    # 比對
    matches = 0
    differences = []
    
    # 建立 ID mapping
    selected_by_id = {}
    for line in selected_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                selected_by_id[id_clean] = line
    
    gt_by_id = {}
    for line in gt_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                gt_by_id[id_clean] = line
    
    # 按 ID 比對
    for id_val in sorted(gt_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in selected_by_id:
            if selected_by_id[id_val] == gt_by_id[id_val]:
                matches += 1
            else:
                differences.append({
                    'id': id_val,
                    'ours': selected_by_id[id_val][:100],
                    'official': gt_by_id[id_val][:100]
                })
    
    total = len(gt_by_id)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print("=" * 80)
    print(f"\n準確率: {matches}/{total} 筆 ({accuracy:.1f}%)")
    print()
    
    if differences:
        print(f"\n剩餘差異 (共 {len(differences)} 筆，顯示前 10 筆):")
        print("-" * 80)
        
        for diff in differences[:10]:
            print(f"\nID: {diff['id']}")
            print(f"  我們: {diff['ours']}")
            print(f"  官方: {diff['official']}")
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\nRESULT: 成功！「Last Clean Wins」策略有效！")
    elif accuracy >= 90:
        print(f"\nRESULT: 接近成功 ({accuracy:.1f}%)，還需微調")
    elif accuracy >= 60:
        print(f"\nRESULT: 有進步 ({accuracy:.1f}%)，但還不夠")
    else:
        print(f"\nRESULT: 策略無效 ({accuracy:.1f}%)")
    
    print("=" * 80)

if __name__ == "__main__":
    test_strategy()

