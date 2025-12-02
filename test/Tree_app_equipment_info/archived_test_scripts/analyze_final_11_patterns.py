#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
深度分析最後 11 筆差異的共同模式
"""

import re

# 讀取數據
pc_by_id = {}
with open('PC_RECEIVED.CSV', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line.startswith('$'):
            continue
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                pc_by_id[id_clean] = line

official_by_id = {}
with open('DATA_2.CSV', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line.startswith('$'):
            continue
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                official_by_id[id_clean] = line

print("=" * 80)
print(" 最後 11 筆差異的深度分析")
print("=" * 80)
print()

# 找出所有差異
all_diffs = []

for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
    if id_val in pc_by_id and pc_by_id[id_val] != official_by_id[id_val]:
        pc_fields = pc_by_id[id_val].split(';')
        off_fields = official_by_id[id_val].split(';')
        
        for idx in range(min(len(pc_fields), len(off_fields))):
            if pc_fields[idx] != off_fields[idx]:
                all_diffs.append({
                    'id': id_val,
                    'field': idx,
                    'pc': pc_fields[idx],
                    'official': off_fields[idx],
                    'pc_full': pc_by_id[id_val],
                    'off_full': official_by_id[id_val]
                })

print(f"總計 {len(all_diffs)} 個欄位差異 (來自 11 個 ID)")
print()

# 分類錯誤類型
error_types = {
    '數字重複': [],      # 例如: '855089' vs '85508'
    '數字多餘': [],      # 例如: '3.710' vs '3.0'
    '額外字元': [],      # 例如: '7' vs ''
    '數字少了': [],      # 例如: '7.04' vs '7.4'
    '字母殘留': [],      # 例如: 'R51R' vs '51R'
    '其他': []
}

for diff in all_diffs:
    pc_val = diff['pc']
    off_val = diff['official']
    
    # 分類
    if not pc_val and off_val:
        error_types['數字少了'].append(diff)
    elif pc_val and not off_val:
        error_types['額外字元'].append(diff)
    elif re.search(r'[A-Z]', pc_val) and not re.search(r'[A-Z]', off_val):
        error_types['字母殘留'].append(diff)
    elif pc_val.replace('.', '').replace('-', '').isdigit() and off_val.replace('.', '').replace('-', '').isdigit():
        # 都是數字，檢查關係
        pc_digits = pc_val.replace('.', '').replace('-', '')
        off_digits = off_val.replace('.', '').replace('-', '')
        
        if len(pc_digits) > len(off_digits) and off_digits in pc_digits:
            error_types['數字重複'].append(diff)
        elif len(pc_digits) > len(off_digits):
            error_types['數字多餘'].append(diff)
        elif len(pc_digits) < len(off_digits):
            error_types['數字少了'].append(diff)
        else:
            error_types['其他'].append(diff)
    else:
        error_types['其他'].append(diff)

# 顯示分類結果
for error_type, errors in error_types.items():
    if errors:
        print(f"\n[{error_type}] 共 {len(errors)} 個")
        print("-" * 80)
        
        for i, err in enumerate(errors[:6], 1):
            print(f"{i}. ID={err['id']}, 欄位[{err['field']}]:")
            print(f"   PC:   '{err['pc']}'")
            print(f"   官方: '{err['official']}'")
            
            # 分析具體模式
            if error_type == '數字重複':
                pc_digits = err['pc'].replace('.', '').replace('-', '')
                off_digits = err['official'].replace('.', '').replace('-', '')
                extra = pc_digits.replace(off_digits, '', 1)
                print(f"   → 多餘數字: '{extra}'")
        
        if len(errors) > 6:
            print(f"   ... 還有 {len(errors) - 6} 個")

print()
print("=" * 80)
print()

# 尋找共同規律
print("共同規律分析：")
print("-" * 80)

if error_types['數字重複']:
    print(f"\n1. 數字重複問題 ({len(error_types['數字重複'])} 個)")
    print("   可能原因：")
    print("   - BLE 封包邊界導致某個數字被切分並重複")
    print("   - 需要檢測「同一數字連續出現」的模式並去重")

if error_types['數字多餘']:
    print(f"\n2. 數字多餘問題 ({len(error_types['數字多餘'])} 個)")
    print("   可能原因：")
    print("   - 小數點後的數字被額外添加")
    print("   - 需要數字格式驗證邏輯")

if error_types['字母殘留']:
    print(f"\n3. 字母殘留問題 ({len(error_types['字母殘留'])} 個)")
    print("   可能原因：")
    print("   - Context-Aware 過濾還有盲點")
    print("   - UTM ZONE 欄位有重複字母 ('R51R' vs '51R')")

print()
print("=" * 80)






