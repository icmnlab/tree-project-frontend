#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
追蹤 ID=10031 的原始 Hex 數據
找出 '15' vs '1' 的數字重複原因
"""

import re

def find_id_10031_in_log(log_file):
    """在 Log 中找到 ID=10031 的所有出現"""
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    # 找到包含 10031 的所有 [BLE RAW] 行
    matching_lines = []
    
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            # 檢查這個 fragment 是否包含 10031
            # 10031 的 hex 是: '1' '0' '0' '3' '1' = 31 30 30 33 31
            hex_part = line.split("[BLE RAW]")[1].strip() if "[BLE RAW]" in line else ""
            
            # 簡單檢查：是否包含 "31 30 30 33 31" 或連續的 "3130303331"
            if "31 30 30 33 31" in hex_part or "3130303331" in hex_part.replace(' ', ''):
                matching_lines.append({
                    'line': line,
                    'hex': hex_part
                })
    
    return matching_lines

def analyze_hex_for_duplication(hex_str):
    """分析 Hex 字串中的數字重複模式"""
    # SEQ 欄位在 field[20]，前面有 19 個分號
    # 在 hex 中，';' = 0x3B，所以我們要找第 20 個 0x3B 後的內容
    
    clean_hex = hex_str.replace(' ', '')
    
    # 轉換為 bytes
    byte_list = []
    for i in range(0, len(clean_hex), 2):
        if i+2 <= len(clean_hex):
            try:
                byte_list.append(int(clean_hex[i:i+2], 16))
            except:
                pass
    
    # 解碼
    try:
        decoded = bytes(byte_list).decode('utf-8', errors='ignore')
    except:
        decoded = bytes(byte_list).decode('latin-1', errors='ignore')
    
    return decoded, byte_list

print("=" * 80)
print(" 追蹤 ID=10031 的數字重複問題")
print("=" * 80)
print()

matches = find_id_10031_in_log('tree_project/project_code/frontend/ble_debug_log.txt')

print(f"找到 {len(matches)} 個包含 ID=10031 的 BLE fragments")
print()

if matches:
    print("詳細分析：")
    print("=" * 80)
    
    for i, match in enumerate(matches, 1):
        print(f"\nFragment {i}:")
        print(f"  Hex: {match['hex'][:100]}")
        
        decoded, byte_list = analyze_hex_for_duplication(match['hex'])
        print(f"  解碼: {decoded[:100]}")
        
        # 找出 SEQ 欄位
        fields = decoded.split(';')
        if len(fields) > 20:
            seq_field = fields[20]
            print(f"  SEQ 欄位 (field[20]): '{seq_field}'")
            
            # 檢查是否包含 '15' 或 '1'
            if '15' in seq_field:
                print(f"    → 發現 '15'！")
                
                # 找出 '15' 在 Hex 中的位置
                # '1' = 0x31, '5' = 0x35
                # 檢查是否有 0x31 0x35 的連續出現
                for j in range(len(byte_list) - 1):
                    if byte_list[j] == 0x31 and byte_list[j+1] == 0x35:
                        # 檢查前後是否有可能導致重複的模式
                        before = byte_list[j-2:j] if j >= 2 else []
                        after = byte_list[j+2:j+4] if j+4 <= len(byte_list) else byte_list[j+2:]
                        
                        print(f"    在 offset {j}: ... {[hex(b) for b in before]} [0x31 0x35] {[hex(b) for b in after]} ...")
print()
print("=" * 80)

