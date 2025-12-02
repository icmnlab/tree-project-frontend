#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
從 Serial Log 追蹤問題 ID 的原始 Hex
找出雜訊字節的確切位置
"""

import re
import os

def parse_serial_log(filepath):
    """解析 Serial Log，返回時間戳和 Hex 數據"""
    entries = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            # 匹配時間戳記 (20:05:53.855)
            match = re.match(r'^(\d{2}:\d{2}:\d{2}\.\d{3})\s+(.+)$', line)
            if match:
                timestamp = match.group(1)
                hex_data = match.group(2)
                entries.append({
                    'time': timestamp,
                    'hex': hex_data
                })
    
    return entries

def hex_to_ascii(hex_str):
    """將 Hex 字串轉為 ASCII"""
    hex_clean = hex_str.replace(' ', '')
    result = []
    for i in range(0, len(hex_clean), 2):
        if i + 2 <= len(hex_clean):
            try:
                byte_val = int(hex_clean[i:i+2], 16)
                if 32 <= byte_val <= 126:
                    result.append(chr(byte_val))
                else:
                    result.append(f'<{byte_val:02X}>')
            except:
                pass
    return ''.join(result)

def find_id_in_serial_log(entries, target_id):
    """在 Serial Log 中找到目標 ID"""
    
    # ID 的 ASCII Hex (e.g. "10087" = "31 30 30 38 37")
    id_ascii_hex = ' '.join([f"{ord(c):02X}" for c in target_id])
    id_hex_compact = id_ascii_hex.replace(' ', '')
    
    found = []
    
    for idx, entry in enumerate(entries):
        hex_compact = entry['hex'].replace(' ', '')
        
        if id_hex_compact in hex_compact:
            found.append({
                'entry_idx': idx,
                'time': entry['time'],
                'hex': entry['hex'],
                'ascii': hex_to_ascii(entry['hex'])
            })
    
    return found

def analyze_problem_field(hex_str, field_name, expected, got):
    """分析問題欄位的 Hex"""
    
    # 將 expected 和 got 轉為 Hex
    expected_hex = ''.join([f"{ord(c):02X}" for c in expected])
    got_hex = ''.join([f"{ord(c):02X}" for c in got])
    
    hex_compact = hex_str.replace(' ', '')
    
    print(f"\n  {field_name} 分析:")
    print(f"    期望: '{expected}' -> Hex: {expected_hex}")
    print(f"    實際: '{got}' -> Hex: {got_hex}")
    
    # 找出在 Hex 中的位置
    if got_hex in hex_compact:
        pos = hex_compact.find(got_hex)
        print(f"    在 Hex 中位置: {pos}")
        
        # 顯示前後文
        context_start = max(0, pos - 20)
        context_end = min(len(hex_compact), pos + len(got_hex) + 20)
        context = hex_compact[context_start:context_end]
        
        # 格式化顯示
        formatted = ' '.join([context[i:i+2] for i in range(0, len(context), 2)])
        print(f"    前後文: {formatted}")
        
        # 標記差異位置
        diff_analysis(expected_hex, got_hex)

def diff_analysis(expected_hex, got_hex):
    """分析 expected 和 got 的 Hex 差異"""
    
    print(f"\n    字節對比:")
    
    # 將 Hex 分解為字節
    exp_bytes = [expected_hex[i:i+2] for i in range(0, len(expected_hex), 2)]
    got_bytes = [got_hex[i:i+2] for i in range(0, len(got_hex), 2)]
    
    # 找出差異
    i = 0
    j = 0
    while i < len(exp_bytes) and j < len(got_bytes):
        if exp_bytes[i] == got_bytes[j]:
            print(f"      [{i}] {exp_bytes[i]} = {got_bytes[j]} ✓")
            i += 1
            j += 1
        else:
            # 差異
            print(f"      [{i}] {exp_bytes[i] if i < len(exp_bytes) else '--'} ≠ {got_bytes[j]} ← 差異!")
            
            # 判斷是插入還是替換
            if j + 1 < len(got_bytes) and (i >= len(exp_bytes) or exp_bytes[i] == got_bytes[j+1]):
                print(f"          → 插入了 {got_bytes[j]} ('{chr(int(got_bytes[j], 16)) if 32 <= int(got_bytes[j], 16) <= 126 else '?'}')")
                j += 1  # 跳過插入的字節
            else:
                i += 1
                j += 1
    
    # 處理剩餘
    while j < len(got_bytes):
        print(f"      [額外] {got_bytes[j]} ← 多餘字節!")
        j += 1

def main():
    base_dir = os.path.dirname(__file__)
    serial_log = os.path.join(base_dir, 'serial_20251125_200547(DATA_2).txt')
    
    print("="*70)
    print(" Serial Log 原始 Hex 追蹤")
    print("="*70)
    
    entries = parse_serial_log(serial_log)
    print(f"\n讀取 {len(entries)} 條 Serial Log 記錄")
    
    # 問題 ID 分析
    problems = [
        ('10071', 'HD', '4.5', '42.5'),
        ('10087', 'UTC', '85508', '855089'),
        ('10092', 'LON', '120.5366472', '120.53664472'),
    ]
    
    for target_id, field, expected, got in problems:
        print(f"\n{'='*70}")
        print(f" ID={target_id} - {field} 欄位")
        print(f"{'='*70}")
        
        found = find_id_in_serial_log(entries, target_id)
        print(f"\n找到 {len(found)} 條包含此 ID 的記錄")
        
        for i, entry in enumerate(found[:3]):
            print(f"\n[{i+1}] 時間: {entry['time']}")
            print(f"    Hex: {entry['hex'][:100]}...")
            print(f"    ASCII: {entry['ascii'][:80]}...")
            
            # 分析問題欄位
            analyze_problem_field(entry['hex'], field, expected, got)
    
    print(f"\n{'='*70}")
    print(" 結論")
    print(f"{'='*70}")
    print("""
分析結果：

1. ID=10071 HD '42.5' vs '4.5':
   - 多了一個 '2' (0x32)
   - 位置在 '4' (0x34) 之後
   - 可能是 PacketLogger 雜訊

2. ID=10087 UTC '855089' vs '85508':
   - 多了一個 '9' (0x39) 在末尾
   - 破壞了 HHMMSS 格式
   - 可用格式驗證修正

3. ID=10092 LON '120.53664472' vs '120.5366472':
   - 多了一個 '4' (0x34)
   - 位置在小數第 4-5 位之間
   - 導致小數位數變成 8 位 (應為 7 位)

通用規則：
- UTC 格式驗證：必須是 6 位數字 (HHMMSS)
- 經度小數驗證：必須是 7 位數字
- HD 範圍驗證：通常 < 100 米 (但不可靠)
""")

if __name__ == "__main__":
    main()
