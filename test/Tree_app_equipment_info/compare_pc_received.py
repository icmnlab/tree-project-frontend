#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
比對 PC_RECEIVED.CSV 和 DATA_2.CSV
"""

import re

# 讀取兩個檔案
pc_lines = []
with open('PC_RECEIVED.CSV', 'r', encoding='utf-8') as f:
    pc_lines = [l.strip() for l in f if l.strip().startswith('$')]

official_lines = []
with open('DATA_2.CSV', 'r', encoding='utf-8') as f:
    official_lines = [l.strip() for l in f if l.strip().startswith('$')]

print("=" * 80)
print(" PC 接收結果 vs 官方 Android App")
print("=" * 80)
print()

print(f"PC 接收: {len(pc_lines)} 筆")
print(f"官方 App: {len(official_lines)} 筆")
print()

# Last Record Wins 比對
pc_by_id = {}
for line in pc_lines:
    fields = line.split(';')
    if len(fields) > 6:
        id_clean = re.sub(r'[^0-9]', '', fields[6])
        if id_clean:
            pc_by_id[id_clean] = line

official_by_id = {}
for line in official_lines:
    fields = line.split(';')
    if len(fields) > 6:
        id_clean = re.sub(r'[^0-9]', '', fields[6])
        if id_clean:
            official_by_id[id_clean] = line

print(f"PC 唯一 ID: {len(pc_by_id)}")
print(f"官方唯一 ID: {len(official_by_id)}")
print()

# 比對
matches = 0
differences = []

for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
    if id_val in pc_by_id:
        if pc_by_id[id_val] == official_by_id[id_val]:
            matches += 1
        else:
            differences.append(id_val)

total = len(official_by_id)
accuracy = matches / total * 100 if total > 0 else 0

print("=" * 80)
print(f"\n準確率: {matches}/{total} = {accuracy:.1f}%")
print()

if differences:
    print(f"有差異的 ID ({len(differences)} 個):")
    print(f"  {differences}")
    print()
    
    # 顯示前 5 個的詳細差異
    print("詳細差異 (前 5 個):")
    print("-" * 80)
    
    for diff_id in differences[:5]:
        print(f"\nID: {diff_id}")
        
        pc_fields = pc_by_id[diff_id].split(';')
        off_fields = official_by_id[diff_id].split(';')
        
        for idx in range(min(len(pc_fields), len(off_fields))):
            if pc_fields[idx] != off_fields[idx]:
                print(f"  欄位[{idx}]: '{pc_fields[idx]}' vs '{off_fields[idx]}'")

print()
print("=" * 80)

if accuracy >= 100:
    print("\n SUCCESS: 100% 完美匹配！可以發布！")
elif accuracy >= 99:
    print(f"\n EXCELLENT: {accuracy:.1f}% - 幾乎完美！")
elif accuracy >= 95:
    print(f"\n GREAT: {accuracy:.1f}% - 非常優秀！")
elif accuracy >= 90:
    print(f"\n GOOD: {accuracy:.1f}% - 良好表現！")

print("=" * 80)






