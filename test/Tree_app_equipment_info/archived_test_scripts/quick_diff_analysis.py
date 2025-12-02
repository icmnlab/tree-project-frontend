#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快速分析問題 ID 的欄位差異"""

import re
import os

def load_csv(filepath):
    data = {}
    if not os.path.exists(filepath):
        return data
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    data[id_clean] = fields
    return data

base_dir = os.path.dirname(__file__)
official = load_csv(os.path.join(base_dir, 'DATA_2.CSV'))
our_v135 = load_csv(os.path.join(base_dir, 'PC_RECEIVED_V135.CSV'))
our_v135plus = load_csv(os.path.join(base_dir, 'PC_RECEIVED_V135_PLUS.CSV'))

print('='*60)
print(' 問題 ID 欄位差異分析')
print('='*60)

problem_ids = ['10071', '10087', '10092']

for pid in problem_ids:
    print(f'\n### ID={pid} ###')
    
    if pid in official:
        off = official[pid]
        print(f'\n官方:')
        print(f'  UTC[19]: "{off[19] if len(off)>19 else "N/A"}"')
        print(f'  LON[14]: "{off[14] if len(off)>14 else "N/A"}"')
        print(f'  HD[24]:  "{off[24] if len(off)>24 else "N/A"}"')
    
    if pid in our_v135:
        our = our_v135[pid]
        print(f'\nV135 (無硬編碼):')
        print(f'  UTC[19]: "{our[19] if len(our)>19 else "N/A"}"')
        print(f'  LON[14]: "{our[14] if len(our)>14 else "N/A"}"')
        print(f'  HD[24]:  "{our[24] if len(our)>24 else "N/A"}"')
        
        # 計算差異
        if pid in official:
            off = official[pid]
            diffs = []
            for i in range(min(len(off), len(our))):
                if off[i] != our[i]:
                    diffs.append(f'[{i}] "{our[i]}" -> "{off[i]}"')
            if diffs:
                print(f'\n  差異:')
                for d in diffs:
                    print(f'    {d}')

print('\n' + '='*60)
print(' 分析雜訊模式')
print('='*60)

# 分析雜訊模式
print('''
ID=10071 HD 問題:
  我們: "42.5"  官方: "4.5"
  多了一個 "2"
  
ID=10087 UTC 問題:
  我們: "855089"  官方: "85508"
  多了一個 "9"
  
ID=10092 LON 問題:
  我們: "120.53664472"  官方: "120.5366472"
  多了一個 "4"

共同點: 都是多了一個數字
''')

# 計算各版本準確率
print('\n' + '='*60)
print(' 版本準確率')
print('='*60)

for name, data in [('V135', our_v135), ('V135+', our_v135plus)]:
    if not data:
        continue
    matches = sum(1 for pid in official if pid in data and ';'.join(data[pid]) == ';'.join(official[pid]))
    total = len(official)
    acc = matches / total * 100
    errors = [pid for pid in official if pid in data and ';'.join(data[pid]) != ';'.join(official[pid])]
    print(f'\n{name}: {acc:.2f}% ({matches}/{total})')
    if errors:
        print(f'  錯誤 ID: {errors}')
