#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
追蹤為什麼 ID=10076, 10087, 10221, 10223 在重建時丟失
"""

import re

def extract_raw_lines_for_id(log_file, target_ids):
    """提取包含目標 ID 的所有 fragments 並重組為完整行"""
    
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    results = {}
    
    for target_id in target_ids:
        # ID 的 Hex
        id_hex_no_space = ''.join([f"{ord(c):02X}" for c in target_id])
        
        # 找到包含此 ID 的所有 fragments
        fragments = []
        
        for line in content.splitlines():
            if "[BLE RAW]" in line:
                hex_part = line.split("[BLE RAW]")[1].strip() if len(line.split("[BLE RAW]")) > 1 else ""
                
                if id_hex_no_space in hex_part.replace(' ', ''):
                    fragments.append(hex_part)
        
        if fragments:
            # 嘗試重組這個 ID 的完整記錄
            # 需要從「包含 ID 的 fragment」向後收集，直到遇到換行
            
            # 找到這個 ID 在整個 Log 中的位置
            all_fragments = []
            id_fragment_index = -1
            
            for idx, line in enumerate(content.splitlines()):
                if "[BLE RAW]" in line:
                    hex_part = line.split("[BLE RAW]")[1].strip() if len(line.split("[BLE RAW]")) > 1 else ""
                    all_fragments.append(hex_part)
                    
                    if id_hex_no_space in hex_part.replace(' ', ''):
                        id_fragment_index = len(all_fragments) - 1
            
            if id_fragment_index >= 0:
                # 從這個 fragment 開始，向後收集直到遇到換行 (0D 0A)
                collected_hex = []
                
                for i in range(id_fragment_index, min(id_fragment_index + 10, len(all_fragments))):
                    hex_str = all_fragments[i].replace(' ', '')
                    
                    # 轉換為 bytes
                    for j in range(0, len(hex_str), 2):
                        if j+2 <= len(hex_str):
                            try:
                                byte_val = int(hex_str[j:j+2], 16)
                                collected_hex.append(byte_val)
                                
                                # 檢查是否遇到換行
                                if byte_val == 0x0A:  # LF
                                    break
                            except:
                                pass
                    
                    # 如果已經遇到換行，停止收集
                    if collected_hex and collected_hex[-1] == 0x0A:
                        break
                
                # 解碼
                try:
                    decoded = bytes(collected_hex).decode('utf-8', errors='ignore')
                except:
                    decoded = bytes(collected_hex).decode('latin-1', errors='ignore')
                
                results[target_id] = {
                    'raw_hex': collected_hex,
                    'decoded': decoded,
                    'has_dollar': (0x24 in collected_hex)  # $ = 0x24
                }
    
    return results

# 追蹤丟失的 ID
lost_ids = ['10076', '10087', '10221', '10223']

print("=" * 80)
print(" 追蹤「丟失」ID 的完整記錄")
print("=" * 80)
print()

results = extract_raw_lines_for_id('tree_project/project_code/frontend/ble_debug_log.txt', lost_ids)

for lost_id in lost_ids:
    if lost_id in results:
        info = results[lost_id]
        
        print(f"\n### ID={lost_id}")
        print(f"  解碼結果:")
        print(f"    {info['decoded'][:120]}")
        print(f"  有 $ 符號: {'YES' if info['has_dollar'] else 'NO'}")
        
        if not info['has_dollar']:
            print(f"  → 問題：缺少 $ 開頭，會被 Structural Filter 過濾掉！")
        
        # 檢查是否有其他結構性問題
        if info['decoded'].strip():
            line = info['decoded'].strip()
            
            # 計算分號數量
            semicolon_count = line.count(';')
            print(f"  分號數量: {semicolon_count} (正常應該 >= 32)")
            
            if semicolon_count < 32:
                print(f"  → 問題：欄位不完整，可能被截斷！")
            
            # 檢查是否以 $ 開頭
            if not line.startswith('$'):
                first_char = line[0] if line else ''
                print(f"  第一個字元: '{first_char}' (應該是 '$')")
                print(f"  → 問題：開頭字元錯誤！")
        
        print("-" * 80)
    else:
        print(f"\n### ID={lost_id}: 無法在 Log 中找到")

print()
print("=" * 80)
print()
print("分析：")
print("  如果缺少 $，代表 $ 被 PacketLogger 雜訊覆蓋或移除")
print("  如果欄位不完整，代表該記錄跨越了多個 BLE 封包但我們重組失敗")
print()
print("=" * 80)






