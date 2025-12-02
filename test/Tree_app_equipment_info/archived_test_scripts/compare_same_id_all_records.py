#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
比對同一個 ID 在兩個數據源中的所有記錄
找出為什麼「Last Record」不同
"""

import re

def extract_all_records_with_id(csv_file):
    """提取所有記錄，保留重複的"""
    records = []
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_str = fields[6].strip()
                # SEQ (field[20])
                seq_str = fields[20].strip() if len(fields) > 20 else ''
                
                records.append({
                    'id': id_str,
                    'seq': seq_str,
                    'line_num': line_num,
                    'line': line
                })
    
    return records

def compare_multi_measurement_ids():
    """比對有多次測量的 ID"""
    print("=" * 80)
    print(" 比對同一 ID 的所有測量記錄")
    print("=" * 80)
    print()
    
    # Wireshark 重建
    dirty_file = 'tree_project/Tree_app_equipment_info/iphone_1st_reconstructed.csv'
    dirty_records = extract_all_records_with_id(dirty_file)
    
    # 官方 App 輸出
    clean_file = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    clean_records = extract_all_records_with_id(clean_file)
    
    print(f"[數據筆數]")
    print(f"  Wireshark: {len(dirty_records)} 筆")
    print(f"  官方 App: {len(clean_records)} 筆")
    print()
    
    # 找出有重複測量的 ID
    from collections import defaultdict
    
    dirty_by_id = defaultdict(list)
    for r in dirty_records:
        dirty_by_id[r['id']].append(r)
    
    clean_by_id = defaultdict(list)
    for r in clean_records:
        clean_by_id[r['id']].append(r)
    
    # 找出同時在兩邊都有重複的 ID
    common_multi_ids = []
    for id_val in dirty_by_id.keys():
        if len(dirty_by_id[id_val]) > 1 and id_val in clean_by_id:
            common_multi_ids.append(id_val)
    
    print(f"[有多次測量的 ID]: {len(common_multi_ids)} 個")
    print()
    
    # 詳細比對前 3 個 ID
    print(f"[詳細比對] (前 3 個 ID):")
    print("=" * 80)
    
    for id_val in sorted(common_multi_ids[:3], key=lambda x: int(re.sub(r'[^0-9]', '', x)) if re.sub(r'[^0-9]', '', x) else 0):
        print(f"\n### ID: {id_val}")
        print()
        
        dirty_recs = dirty_by_id[id_val]
        clean_recs = clean_by_id[id_val] if id_val in clean_by_id else []
        
        print(f"Wireshark ({len(dirty_recs)} 筆):")
        for i, r in enumerate(dirty_recs, 1):
            # 計算雜訊
            noise_count = len(re.findall(r'[A-Z]', r['line'].split(';')[23] if len(r['line'].split(';')) > 23 else ''))
            print(f"  {i}. SEQ={r['seq']}, Line={r['line_num']}")
            print(f"     {r['line'][:120]}")
            if noise_count > 0:
                print(f"     [Noise: {noise_count} letters]")
        
        print()
        print(f"官方 App ({len(clean_recs)} 筆):")
        for i, r in enumerate(clean_recs, 1):
            print(f"  {i}. SEQ={r['seq']}, Line={r['line_num']}")
            print(f"     {r['line'][:120]}")
        
        # 比對 Last Record
        if dirty_recs and clean_recs:
            last_dirty = dirty_recs[-1]['line']
            last_clean = clean_recs[-1]['line']
            
            print()
            if last_dirty == last_clean:
                print("  LAST RECORD: 相同")
            else:
                print("  LAST RECORD: 不同！")
                print(f"    Wireshark最後: {last_dirty[:100]}")
                print(f"    官方App最後:   {last_clean[:100]}")
        
        print("-" * 80)
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    compare_multi_measurement_ids()






