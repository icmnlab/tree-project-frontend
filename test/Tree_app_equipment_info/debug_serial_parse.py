#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Debug Serial Log 解析
輸出清洗後的原始數據，找出問題所在
"""

import re

def parse_serial_log(filepath):
    """解析 Serial Log"""
    all_bytes = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            
            # 移除時間戳記
            line = re.sub(r'^\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s*', '', line)
            
            # 分割成 tokens
            tokens = line.split()
            
            for token in tokens:
                for i in range(0, len(token), 2):
                    if i + 2 <= len(token):
                        hex_str = token[i:i+2]
                        try:
                            byte_val = int(hex_str, 16)
                            all_bytes.append(byte_val)
                        except ValueError:
                            pass
    
    return all_bytes

def apply_filter(data_stream):
    """套用過濾器"""
    cleaned_data = []
    i = 0
    
    while i < len(data_stream):
        # 偵測封包頭
        is_header = False
        if i + 2 < len(data_stream):
            if (data_stream[i] == 0x44 and data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00) or \
               (data_stream[i] == 0x44 and data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00):
                is_header = True
                
                # 回溯清理
                if len(cleaned_data) >= 2 and (cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E):
                    cleaned_data.pop()
                    cleaned_data.pop()
                elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                    cleaned_data.pop()
                
                i += 3
                continue
        
        # 過濾獨立 Non-ASCII
        if data_stream[i] > 0x7E and data_stream[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_data.append(data_stream[i])
        i += 1
    
    return cleaned_data

# 主程式
serial_log = 'tree_project/Tree_app_equipment_info/serial_20251125_200547(DATA_2).txt'

print("解析 Serial Log...")
data_stream = parse_serial_log(serial_log)
print(f"原始: {len(data_stream)} bytes")

print("\n套用過濾器...")
cleaned_data = apply_filter(data_stream)
print(f"清洗後: {len(cleaned_data)} bytes")

print("\n解碼...")
try:
    decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    print(f"解碼成功: {len(decoded_text)} 字元")
except Exception as e:
    print(f"解碼失敗: {e}")
    decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')

# 輸出前 2000 字元查看
print("\n前 2000 字元:")
print("=" * 80)
print(decoded_text[:2000])
print("=" * 80)

# 計算資料行
data_lines = [line for line in decoded_text.split('\n') if line.strip().startswith('$')]
print(f"\n找到 {len(data_lines)} 筆資料行")

if data_lines:
    print("\n前 5 筆:")
    for i, line in enumerate(data_lines[:5], 1):
        print(f"{i}. {line[:100]}")

# 儲存清洗後的完整文本
with open('tree_project/Tree_app_equipment_info/serial_cleaned_debug.txt', 'w', encoding='utf-8') as f:
    f.write(decoded_text)
print(f"\n已儲存完整文本至: serial_cleaned_debug.txt")






