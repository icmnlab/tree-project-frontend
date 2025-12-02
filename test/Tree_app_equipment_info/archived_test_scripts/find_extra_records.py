#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
找出官方 App 多出來的 16 筆數據是什麼
這可能是理解其過濾策略的關鍵
"""

import re

def extract_ids(csv_file):
    """提取所有記錄的 ID"""
    ids = []
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_raw = fields[6].strip()
                # 清理 ID (移除非數字)
                id_clean = re.sub(r'[^0-9]', '', id_raw)
                if id_clean:
                    ids.append({
                        'id': id_clean,
                        'id_raw': id_raw,
                        'line': line[:100]
                    })
    
    return ids

def compare_id_lists():
    """比對兩個列表的 ID"""
    print("=" * 80)
    print(" 尋找官方 App 多出來的 16 筆數據")
    print("=" * 80)
    print()
    
    # Wireshark 重建（髒數據）
    dirty_file = 'tree_project/Tree_app_equipment_info/iphone_1st_reconstructed.csv'
    dirty_ids = extract_ids(dirty_file)
    
    # 官方 App 輸出（乾淨數據）
    clean_file = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    clean_ids = extract_ids(clean_file)
    
    print(f"[數據筆數]")
    print(f"  Wireshark 重建: {len(dirty_ids)} 筆")
    print(f"  官方 App 輸出: {len(clean_ids)} 筆")
    print(f"  差異: {len(clean_ids) - len(dirty_ids)} 筆")
    print()
    
    # 建立 ID 集合
    dirty_id_set = set([r['id'] for r in dirty_ids])
    clean_id_set = set([r['id'] for r in clean_ids])
    
    print(f"[唯一 ID 數量]")
    print(f"  Wireshark: {len(dirty_id_set)} 個")
    print(f"  官方 App: {len(clean_id_set)} 個")
    print()
    
    # 找出官方 App 多出來的 ID
    extra_ids = clean_id_set - dirty_id_set
    missing_ids = dirty_id_set - clean_id_set
    
    if extra_ids:
        print(f"[官方 App 多出來的 ID] ({len(extra_ids)} 個):")
        for id_val in sorted(extra_ids, key=lambda x: int(x) if x.isdigit() else 0)[:20]:
            # 找到對應的完整行
            for r in clean_ids:
                if r['id'] == id_val:
                    print(f"  ID: {id_val} (raw: '{r['id_raw']}')")
                    print(f"    {r['line']}")
                    break
        print()
    
    if missing_ids:
        print(f"[Wireshark 重建多出來的 ID] ({len(missing_ids)} 個):")
        for id_val in sorted(missing_ids, key=lambda x: int(x) if x.isdigit() else 0)[:20]:
            for r in dirty_ids:
                if r['id'] == id_val:
                    print(f"  ID: {id_val} (raw: '{r['id_raw']}')")
                    print(f"    {r['line']}")
                    break
        print()
    
    # 統計重複 ID
    from collections import Counter
    
    dirty_id_counts = Counter([r['id'] for r in dirty_ids])
    clean_id_counts = Counter([r['id'] for r in clean_ids])
    
    dirty_duplicates = {id: count for id, count in dirty_id_counts.items() if count > 1}
    clean_duplicates = {id: count for id, count in clean_id_counts.items() if count > 1}
    
    print(f"[重複 ID 統計]")
    print(f"  Wireshark 有重複的 ID: {len(dirty_duplicates)} 個")
    if dirty_duplicates:
        print(f"    範例: {list(dirty_duplicates.items())[:10]}")
    print()
    print(f"  官方 App 有重複的 ID: {len(clean_duplicates)} 個")
    if clean_duplicates:
        print(f"    範例: {list(clean_duplicates.items())[:10]}")
    print()
    
    print("=" * 80)
    
    print("\n[分析]")
    if len(extra_ids) > 0 and len(missing_ids) > 0:
        print("官方 App 同時有多出和缺少的 ID。")
        print("這可能表示：")
        print("  1. Wireshark 抓包可能丟失了某些封包")
        print("  2. 或者兩次測試使用了不同的數據集")
    elif len(clean_ids) > len(dirty_ids):
        print("官方 App 的數據更完整！")
        print("這可能表示：")
        print("  1. Wireshark 抓包丟失了某些封包")
        print("  2. 或官方 App 有重新請求機制")
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    compare_id_lists()






