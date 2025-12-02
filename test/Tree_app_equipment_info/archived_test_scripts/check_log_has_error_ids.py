#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查我們的 Log 是否包含剩餘有差異的 10 個 ID
"""

import re

# 從 Log 提取所有 ID
with open('tree_project/project_code/frontend/ble_debug_log.txt', 'r', encoding='utf-16') as f:
    content = f.read()

# 尋找 ID 模式：;;;; 後跟數字 ;;;;
# VLGEO 格式: $;STATUS;TYPE;PROD;VER;SNR;ID;...
# ID 在 field[6]，前面有 6 個分號

ids_in_log = set()

# 簡單搜尋：找到所有包含 "10053", "10071" 等的行
test_ids = ['10053', '10071', '10076', '10087', '10092', '10221', '10223', '10232', '10242', '10063']

print("檢查 Log 中是否包含剩餘有差異的 ID：")
print("=" * 80)

for test_id in test_ids:
    if test_id in content:
        print(f"ID {test_id}: 在 Log 中")
    else:
        print(f"ID {test_id}: 不在 Log 中！")

print()
print("=" * 80)






