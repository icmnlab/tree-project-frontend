#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
比對我們的 Log vs 官方數據的記錄完整性
檢查我們是否遺漏了某些重傳記錄
"""

import re
from collections import defaultdict

def extract_from_log(log_file):
    """從 Log 提取所有記錄（包含重複）"""
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    # 重組byte stream
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    # v13.2 過濾器
    cleaned_data = []
    i = 0
    
    while i < len(full_byte_stream):
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                
                if len(cleaned_data) >= 2 and (cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E):
                    cleaned_data.pop()
                    cleaned_data.pop()
                elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                    cleaned_data.pop()
                
                i += 3
                continue
        
        if full_byte_stream[i] > 0x7E and full_byte_stream[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_data.append(full_byte_stream[i])
        i += 1
    
    # 解碼
    try:
        decoded_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # String-Level 白名單
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # Field-Specific 過濾
    records = []
    for line in cleaned_text.split('\n'):
        line = line.strip()
        if not line.startswith('$') or len(line) <= 10:
            continue
        
        fields = line.split(';')
        
        # 清理
        for idx in range(len(fields)):
            if idx not in [2, 13, 15, 32]:
                fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
            
            if idx == 2:
                type_val = fields[idx]
                if type_val and type_val not in ['1P', '3P', '3D', 'DME', '']:
                    for valid_type in ['1P', '3P', '3D', 'DME']:
                        if valid_type in type_val:
                            fields[idx] = valid_type
                            break
        
        cleaned_line = ';'.join(fields)
        
        # 提取 ID 和 SEQ
        id_clean = re.sub(r'[^0-9]', '', fields[6]) if len(fields) > 6 else ''
        seq = fields[20].strip() if len(fields) > 20 else ''
        
        if id_clean:
            records.append({
                'id': id_clean,
                'seq': seq,
                'line': cleaned_line
            })
    
    return records

def compare_completeness():
    """比對記錄完整性"""
    print("=" * 80)
    print(" 比對記錄完整性")
    print("=" * 80)
    print()
    
    # 1. 從我們的 Log 提取
    print("[Step 1] 從我們的 ble_debug_log.txt 提取...")
    our_records = extract_from_log('tree_project/project_code/frontend/ble_debug_log.txt')
    print(f"  我們的 Log: {len(our_records)} 筆")
    
    # 統計 ID
    our_id_counts = defaultdict(list)
    for r in our_records:
        our_id_counts[r['id']].append(r)
    
    print(f"  唯一 ID: {len(our_id_counts)} 個")
    print(f"  有多次測量的 ID: {sum(1 for recs in our_id_counts.values() if len(recs) > 1)} 個")
    print()
    
    # 2. 從官方數據提取
    print("[Step 2] 從官方 DATA_2.CSV 提取...")
    
    official_records = []
    with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            id_clean = re.sub(r'[^0-9]', '', fields[6]) if len(fields) > 6 else ''
            seq = fields[20].strip() if len(fields) > 20 else ''
            
            if id_clean:
                official_records.append({
                    'id': id_clean,
                    'seq': seq,
                    'line': line
                })
    
    print(f"  官方數據: {len(official_records)} 筆")
    
    official_id_counts = defaultdict(list)
    for r in official_records:
        official_id_counts[r['id']].append(r)
    
    print(f"  唯一 ID: {len(official_id_counts)} 個")
    print(f"  有多次測量的 ID: {sum(1 for recs in official_id_counts.values() if len(recs) > 1)} 個")
    print()
    
    # 3. 比對有多次測量的 ID
    print("[Step 3] 比對重複測量的 ID...")
    print("=" * 80)
    print()
    
    for id_val in sorted(official_id_counts.keys(), key=lambda x: int(x) if x.isdigit() else 0)[:15]:
        our_recs = our_id_counts.get(id_val, [])
        official_recs = official_id_counts[id_val]
        
        if len(official_recs) > 1:
            print(f"ID {id_val}:")
            print(f"  我們: {len(our_recs)} 筆, SEQ={[r['seq'] for r in our_recs]}")
            print(f"  官方: {len(official_recs)} 筆, SEQ={[r['seq'] for r in official_recs]}")
            
            if len(our_recs) != len(official_recs):
                print(f"  WARNING: 筆數不符！我們可能遺漏了某些重傳")
            print()
    
    print("=" * 80)
    
    # 4. 關鍵發現
    print("\n[關鍵發現]")
    print("-" * 80)
    
    total_ours = len(our_records)
    total_official = len(official_records)
    
    if total_ours < total_official:
        missing = total_official - total_ours
        print(f"我們的 Log 遺漏了 {missing} 筆記錄 ({missing/total_official*100:.1f}%)")
        print("這些遺漏的記錄可能就是「乾淨的重傳版本」！")
    elif total_ours == total_official:
        print("記錄筆數相同，但準確率不同。")
        print("問題可能是：")
        print("  1. 我們的過濾器還不夠完善")
        print("  2. 官方 App 有智能數字驗證邏輯")
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    compare_completeness()

