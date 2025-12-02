#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查有差異的 ID 是否有重複測量
如果官方數據中有多次測量，說明儀器重傳了乾淨的版本
"""

import re
from collections import defaultdict

def get_all_records(csv_file):
    """提取所有記錄（包含重複）"""
    records = []
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_str = fields[6].strip()
                id_clean = re.sub(r'[^0-9]', '', id_str)
                seq_str = fields[20].strip() if len(fields) > 20 else ''
                
                if id_clean:
                    records.append({
                        'id': id_clean,
                        'seq': seq_str,
                        'line': line
                    })
    
    return records

# 讀取官方數據
print("檢查官方數據中的重複測量情況...")
print("=" * 80)
print()

official_records = get_all_records('tree_project/Tree_app_equipment_info/DATA_2.CSV')

# 統計每個 ID 的測量次數
id_counts = defaultdict(list)
for r in official_records:
    id_counts[r['id']].append(r)

print(f"總筆數: {len(official_records)}")
print(f"唯一 ID: {len(id_counts)}")
print()

# 找出有多次測量的 ID
multi_measurement = {id_val: recs for id_val, recs in id_counts.items() if len(recs) > 1}

print(f"有多次測量的 ID: {len(multi_measurement)} 個")
print()

if multi_measurement:
    print("範例：")
    for id_val in sorted(multi_measurement.keys(), key=lambda x: int(x) if x.isdigit() else 0)[:10]:
        recs = multi_measurement[id_val]
        print(f"\nID {id_val}: {len(recs)} 次測量")
        for i, r in enumerate(recs, 1):
            print(f"  {i}. SEQ={r['seq']}: {r['line'][:80]}")

# 檢查我們有差異的 ID 是否在多次測量列表中
print()
print("=" * 80)
print("\n檢查「有差異的 ID」是否有重複測量...")

# 這是剛才發現有差異的 ID 列表
error_ids = ['10024', '10031', '10034', '10042', '10053', '10063', '10071', '10076', '10087', '10092', '10138']

for error_id in error_ids:
    if error_id in multi_measurement:
        recs = multi_measurement[error_id]
        print(f"\nID {error_id}: ✓ 有 {len(recs)} 次測量（Last Record Wins 應該會修正）")
    else:
        print(f"ID {error_id}: ✗ 只有 1 次測量（無法靠重傳修正）")

print()
print("=" * 80)






