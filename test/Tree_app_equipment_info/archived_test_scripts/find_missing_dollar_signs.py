#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
找出為什麼 $ 符號消失了
"""

import re

def parse_first_few_lines(filepath):
    """解析前幾行，詳細追蹤"""
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()[:10]  # 只看前 10 行
    
    for line_num, line in enumerate(lines, 1):
        line = line.strip()
        if not line:
            continue
        
        print(f"\n=== Line {line_num} ===")
        
        # 移除時間戳記
        line = re.sub(r'^\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s*', '', line)
        
        # 分割成 tokens
        tokens = line.split()
        
        print(f"Tokens: {len(tokens)}")
        
        # 解析前 20 個 bytes
        all_bytes = []
        for token in tokens[:20]:
            for i in range(0, len(token), 2):
                if i + 2 <= len(token):
                    hex_str = token[i:i+2]
                    try:
                        byte_val = int(hex_str, 16)
                        all_bytes.append(byte_val)
                    except ValueError:
                        pass
        
        print(f"前 20 bytes (hex): {' '.join([f'{b:02X}' for b in all_bytes[:20]])}")
        
        # 檢查是否有 $ (0x24)
        if 0x24 in all_bytes:
            pos = all_bytes.index(0x24)
            print(f"找到 $ 在位置 {pos}")
            
            # 檢查前後
            if pos > 0:
                print(f"  前一個 byte: 0x{all_bytes[pos-1]:02X}")
            if pos + 1 < len(all_bytes):
                print(f"  後一個 byte: 0x{all_bytes[pos+1]:02X}")
        else:
            print("未找到 $")
        
        # 嘗試解碼
        try:
            decoded = bytes(all_bytes[:40]).decode('utf-8', errors='ignore')
            print(f"解碼: {decoded[:60]}")
        except:
            pass

# 執行
parse_first_few_lines('tree_project/Tree_app_equipment_info/serial_20251125_200547(DATA_2).txt')






