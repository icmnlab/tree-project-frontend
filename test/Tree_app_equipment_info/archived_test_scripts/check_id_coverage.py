#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查我們重建的數據 vs 官方數據的 ID 覆蓋範圍
"""

import re

def get_ids(csv_file):
    """提取所有唯一 ID"""
    ids = set()
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    ids.add(id_clean)
    
    return ids

# 我們重建的
ours_file = 'tree_project/Tree_app_equipment_info/reconstructed_from_log.csv'
try:
    ours_ids = get_ids(ours_file)
    print(f"我們的數據 ID 範圍: {min(ours_ids, key=int)} - {max(ours_ids, key=int)} ({len(ours_ids)} 個)")
except:
    print("無法讀取 reconstructed_from_log.csv")

# 官方的
official_file = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
official_ids = get_ids(official_file)
print(f"官方數據 ID 範圍: {min(official_ids, key=int)} - {max(official_ids, key=int)} ({len(official_ids)} 個)")

# 我們缺少的 ID
missing = official_ids - ours_ids if 'ours_ids' in locals() else official_ids
if missing:
    print(f"\n我們缺少的 ID ({len(missing)} 個):")
    for id_val in sorted(missing, key=int)[:20]:
        print(f"  {id_val}")






