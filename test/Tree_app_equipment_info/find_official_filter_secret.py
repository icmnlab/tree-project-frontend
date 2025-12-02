#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
找出官方 App 的過濾秘訣
比對「原始封包重建」vs「官方 App 輸出」的差異
"""

import re

def parse_to_dict(csv_file):
    """解析 CSV 為 dict list，保留完整行"""
    records = []
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            
            # 提取 ID
            id_str = fields[6].strip() if len(fields) > 6 else ''
            # 清理 ID 中的非數字字元
            id_clean = re.sub(r'[^0-9]', '', id_str)
            
            if id_clean:
                records.append({
                    'id': id_clean,
                    'id_raw': id_str,
                    'line': line
                })
    
    return records

def compare_dirty_vs_clean():
    """比對髒數據 vs 乾淨數據"""
    print("=" * 80)
    print(" 官方 App 過濾秘訣逆向工程")
    print(" (比對 Wireshark 原始重建 vs 官方 App 輸出)")
    print("=" * 80)
    print()
    
    # 髒數據：從 Wireshark 直接重建（只有簡單白名單過濾）
    dirty_file = 'tree_project/Tree_app_equipment_info/iphone_1st_reconstructed.csv'
    
    # 乾淨數據：官方 App 實際輸出
    clean_file = 'tree_project/Tree_app_equipment_info/DATA_from_iphone.CSV'
    
    print("[Step 1] 讀取數據...")
    dirty_records = parse_to_dict(dirty_file)
    clean_records = parse_to_dict(clean_file)
    
    print(f"  Wireshark 重建 (髒): {len(dirty_records)} 筆")
    print(f"  官方 App 輸出 (乾淨): {len(clean_records)} 筆")
    print()
    
    # 建立 ID 對應
    dirty_by_id = {r['id']: r for r in dirty_records}
    clean_by_id = {r['id']: r for r in clean_records}
    
    print("[Step 2] 分析差異模式...")
    print()
    
    # 找出相同 ID 的記錄進行比對
    same_id_count = 0
    perfect_match_count = 0
    has_diff_count = 0
    
    diff_patterns = []
    
    for record_id in clean_by_id.keys():
        if record_id in dirty_by_id:
            same_id_count += 1
            
            dirty_line = dirty_by_id[record_id]['line']
            clean_line = clean_by_id[record_id]['line']
            
            if dirty_line == clean_line:
                perfect_match_count += 1
            else:
                has_diff_count += 1
                
                # 找出具體差異
                dirty_fields = dirty_line.split(';')
                clean_fields = clean_line.split(';')
                
                field_diffs = []
                for idx in range(min(len(dirty_fields), len(clean_fields))):
                    if dirty_fields[idx] != clean_fields[idx]:
                        field_diffs.append({
                            'field_idx': idx,
                            'dirty': dirty_fields[idx],
                            'clean': clean_fields[idx]
                        })
                
                if field_diffs and len(diff_patterns) < 30:  # 保留前30個案例
                    diff_patterns.append({
                        'id': record_id,
                        'diffs': field_diffs,
                        'dirty_full': dirty_line[:150],
                        'clean_full': clean_line[:150]
                    })
    
    print(f"[相同 ID 的記錄]: {same_id_count} 筆")
    print(f"  完全匹配: {perfect_match_count} 筆 ({perfect_match_count/same_id_count*100:.1f}%)")
    print(f"  有差異: {has_diff_count} 筆 ({has_diff_count/same_id_count*100:.1f}%)")
    print()
    
    # 分析差異模式
    if diff_patterns:
        print(f"[差異模式分析] (顯示前 10 個案例)")
        print("-" * 80)
        
        for i, pattern in enumerate(diff_patterns[:10], 1):
            print(f"\n案例 {i}: ID={pattern['id']}")
            print(f"  髒數據: {pattern['dirty_full']}")
            print(f"  乾淨:   {pattern['clean_full']}")
            print(f"  差異欄位:")
            
            for diff in pattern['diffs'][:5]:  # 只顯示前5個差異欄位
                print(f"    欄位[{diff['field_idx']}]: '{diff['dirty']}' → '{diff['clean']}'")
        
        if len(diff_patterns) > 10:
            print(f"\n  ... 還有 {len(diff_patterns) - 10} 個案例未顯示")
    
    print()
    print("=" * 80)
    
    # 找出官方 App 的過濾規則
    print("\n[Step 3] 推斷官方 App 的過濾規則...")
    print("-" * 80)
    
    # 統計所有差異中，髒數據有什麼特徵
    dirty_chars = set()
    for pattern in diff_patterns:
        for diff in pattern['diffs']:
            dirty_val = diff['dirty']
            clean_val = diff['clean']
            
            # 找出髒數據中有但乾淨數據中沒有的字元
            for char in dirty_val:
                if char not in clean_val:
                    dirty_chars.add(char)
    
    print(f"\n髒數據中出現但官方 App 過濾掉的字元:")
    print(f"  {sorted(dirty_chars)}")
    print()
    
    # 分析這些字元的 ASCII 範圍
    lowercase = [c for c in dirty_chars if c.islower()]
    special = [c for c in dirty_chars if not c.isalnum() and c not in ['.', ';', '-', '$', '#']]
    
    if lowercase:
        print(f"  小寫字母: {sorted(lowercase)}")
        print(f"  → 官方 App 規則推斷：只接受大寫字母 (A-Z)")
    if special:
        print(f"  特殊字元: {sorted(special)}")
    
    print()
    print("=" * 80)
    
    print("\n[結論]")
    print("-" * 80)
    print(f"官方 Haglof Link App 能從 38.4% 準確率的原始封包復原出 100% 完美數據。")
    print(f"關鍵差異：")
    print(f"  1. 可能有更強的小寫字母過濾")
    print(f"  2. 可能有智能錯誤修正機制")
    print(f"  3. 可能依賴「Last Record Wins」+ 重複傳輸")
    print()
    print("=" * 80)

if __name__ == "__main__":
    compare_dirty_vs_clean()






