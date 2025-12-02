#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
找出「丟失」的 6 個 ID 在 Log 中的位置
它們一定存在，只是被我們的處理邏輯弄丟了
"""

import re

def search_id_in_raw_log(log_file, target_id):
    """在原始 Log 中搜尋 ID（Hex 格式）"""
    
    # ID 的 ASCII 表示法
    # 例如 "10076" = 31 30 30 37 36
    id_hex = ' '.join([f"{ord(c):02X}" for c in target_id])
    id_hex_no_space = ''.join([f"{ord(c):02X}" for c in target_id])
    
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    # 搜尋包含此 ID 的 [BLE RAW] 行
    matching_lines = []
    
    for line_num, line in enumerate(content.splitlines(), 1):
        if "[BLE RAW]" in line:
            hex_part = line.split("[BLE RAW]")[1].strip() if len(line.split("[BLE RAW]")) > 1 else ""
            
            # 檢查是否包含 ID（有空格或無空格）
            if id_hex in hex_part or id_hex_no_space in hex_part.replace(' ', ''):
                matching_lines.append({
                    'line_num': line_num,
                    'hex': hex_part
                })
    
    return matching_lines

# 測試「丟失」的 ID
lost_ids = ['10076', '10087', '10221', '10223', '10242', '10063']

print("=" * 80)
print(" 追蹤「丟失」的 6 個 ID")
print("=" * 80)
print()

for lost_id in lost_ids:
    print(f"\n### 搜尋 ID={lost_id}")
    
    matches = search_id_in_raw_log('tree_project/project_code/frontend/ble_debug_log.txt', lost_id)
    
    if matches:
        print(f"  找到 {len(matches)} 個 fragments")
        for i, match in enumerate(matches[:3], 1):
            print(f"  Fragment {i} (Line {match['line_num']}):")
            print(f"    Hex: {match['hex'][:100]}")
            
            # 解碼
            clean_hex = match['hex'].replace(' ', '')
            byte_list = []
            for j in range(0, len(clean_hex), 2):
                if j+2 <= len(clean_hex):
                    try:
                        byte_list.append(int(clean_hex[j:j+2], 16))
                    except:
                        pass
            
            try:
                decoded = bytes(byte_list).decode('utf-8', errors='ignore')
                print(f"    解碼: {decoded[:80]}")
            except:
                pass
        
        if len(matches) > 3:
            print(f"  ... 還有 {len(matches) - 3} 個")
    else:
        print(f"  未找到！(這個 ID 真的不在 Log 中)")

print()
print("=" * 80)
print()
print("結論：")
print("  如果所有 ID 都能找到 → 問題在我們的解析/過濾邏輯")
print("  如果有 ID 找不到 → Log 確實不完整")
print()
print("=" * 80)






