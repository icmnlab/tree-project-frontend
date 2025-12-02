#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查剩餘的 11 筆差異是否有重複測量
如果有，這些差異應該會被 Last Record Wins 自動修正
"""

import re
from collections import defaultdict

# 剩餘有差異的 ID
remaining_error_ids = ['10053', '10063', '10071', '10076', '10087', '10092', '10221', '10223', '10232', '10242']

print("=" * 80)
print(" 檢查剩餘 11 筆差異是否有重複測量")
print("=" * 80)
print()

# 讀取官方數據（所有記錄，包含重複）
official_all_records = []
with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line.startswith('$'):
            continue
        
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            seq = fields[20] if len(fields) > 20 else ''
            
            if id_clean:
                official_all_records.append({
                    'id': id_clean,
                    'seq': seq,
                    'line': line
                })

# 統計每個 ID 的測量次數
id_counts = defaultdict(list)
for r in official_all_records:
    id_counts[r['id']].append(r)

print(f"檢查結果：")
print("-" * 80)

has_retransmission = []
no_retransmission = []

for error_id in remaining_error_ids:
    if error_id in id_counts:
        recs = id_counts[error_id]
        if len(recs) > 1:
            has_retransmission.append(error_id)
            print(f"\nID {error_id}: 有 {len(recs)} 次測量 (可能被 Last Record Wins 修正)")
            for i, r in enumerate(recs, 1):
                print(f"  {i}. SEQ={r['seq']}: {r['line'][:80]}")
        else:
            no_retransmission.append(error_id)
            print(f"\nID {error_id}: 只有 1 次測量 (無法靠重傳修正)")
            print(f"  {recs[0]['line'][:100]}")
    else:
        print(f"\nID {error_id}: 在官方數據中找不到！")

print()
print("=" * 80)
print()
print(f"統計：")
print(f"  有重複測量（可自動修正）: {len(has_retransmission)} 個 - {has_retransmission}")
print(f"  無重複測量（需手動修正）: {len(no_retransmission)} 個 - {no_retransmission}")
print()

if len(no_retransmission) == 0:
    print("結論: 所有剩餘差異都有重複測量！")
    print("→ Last Record Wins 機制會自動修正這些差異")
    print("→ v13.2 + Last Record Wins 理論上可達到 100%！")
elif len(no_retransmission) <= 3:
    print(f"結論: 只有 {len(no_retransmission)} 筆無重複測量，其他都能自動修正")
    print("→ 實際準確率會遠高於 96.7%！")
else:
    print(f"結論: 有 {len(no_retransmission)} 筆無法靠重傳修正")
    print("→ 需要進一步優化過濾器")

print("=" * 80)






