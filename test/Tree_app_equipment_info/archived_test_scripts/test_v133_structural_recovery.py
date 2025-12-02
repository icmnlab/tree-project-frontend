#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
v13.3 Structural Recovery 過濾器
即使缺少 $，也能辨識並恢復有效的數據行
"""

import re

def apply_v133_filter(log_file):
    """v13.3 完整過濾器"""
    
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    # 提取 fragments
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    # 重組 byte stream
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    # === Byte-Level 過濾（兩階段）===
    
    # Stage 1: 封包頭 + 回溯
    cleaned_stage1 = []
    i = 0
    
    while i < len(full_byte_stream):
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                
                if len(cleaned_stage1) >= 2 and (cleaned_stage1[-1] > 0x7E or cleaned_stage1[-2] > 0x7E):
                    cleaned_stage1.pop()
                    cleaned_stage1.pop()
                elif len(cleaned_stage1) == 1 and cleaned_stage1[-1] > 0x7E:
                    cleaned_stage1.pop()
                
                i += 3
                continue
        
        cleaned_stage1.append(full_byte_stream[i])
        i += 1
    
    # Stage 2: 全域配對清理
    cleaned_stage2 = []
    i = 0
    
    while i < len(cleaned_stage1):
        if i + 1 < len(cleaned_stage1):
            current_byte = cleaned_stage1[i]
            next_byte = cleaned_stage1[i+1]
            
            if current_byte > 0x7E and current_byte not in [0x0D, 0x0A]:
                if 0x20 <= next_byte <= 0x7E:
                    i += 2  # 配對雜訊，兩個都移除
                    continue
                else:
                    i += 1  # 只移除 Non-ASCII
                    continue
        
        if cleaned_stage1[i] > 0x7E and cleaned_stage1[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_stage2.append(cleaned_stage1[i])
        i += 1
    
    # === 解碼 ===
    try:
        decoded_text = bytes(cleaned_stage2).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_stage2).decode('latin-1', errors='ignore')
    
    # String-Level 白名單
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    
    # === v13.3 NEW: Structural Recovery ===
    # 不只檢查 $，還要檢查結構模式
    
    recovered_lines = []
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        
        if len(line) <= 10:
            continue
        
        # 原有邏輯：正常的 $ 開頭行
        if line.startswith('$'):
            recovered_lines.append(line)
            continue
        
        # v13.3 NEW: 智能結構匹配
        # 檢查是否符合 VLGEO 數據模式：
        # ;STATUS;TYPE;;;;ID;;;;;;LAT;N/S;LON;E/W;...
        
        # 檢查條件：
        # 1. 有足夠的分號 (至少 20 個)
        # 2. field[2] 是合法 TYPE (1P, 3P, 3D, DME)
        # 3. field[6] 是數字 ID
        
        if line.count(';') >= 20:
            fields = line.split(';')
            
            # 檢查 TYPE 欄位
            type_field = fields[2] if len(fields) > 2 else ''
            # 檢查 ID 欄位
            id_field = fields[6] if len(fields) > 6 else ''
            id_clean = re.sub(r'[^0-9]', '', id_field)
            
            # 如果 TYPE 看起來合法，且 ID 是數字
            if type_field in ['1P', '3P', '3D', 'DME', ''] or \
               any(valid_type in type_field for valid_type in ['1P', '3P', '3D', 'DME']):
                if id_clean and len(id_clean) >= 1:
                    # 這看起來是有效的數據行！補上 $
                    recovered_line = '$' + line
                    recovered_lines.append(recovered_line)
                    continue
        
        # 不符合任何模式，丟棄
    
    # === Field-Specific 清理 ===
    cleaned_lines = []
    
    for line in recovered_lines:
        fields = line.split(';')
        
        # 清理數字欄位中的字母
        for idx in range(len(fields)):
            if idx not in [2, 13, 15, 32]:
                fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
            
            # TYPE 欄位修正
            if idx == 2:
                type_val = fields[idx]
                if type_val and type_val not in ['1P', '3P', '3D', 'DME', '']:
                    for valid_type in ['1P', '3P', '3D', 'DME']:
                        if valid_type in type_val:
                            fields[idx] = valid_type
                            break
        
        cleaned_lines.append(';'.join(fields))
    
    # === Last Record Wins ===
    id_records = {}
    
    for line in cleaned_lines:
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                id_records[id_clean] = line
    
    return id_records

def test_v133():
    """測試 v13.3"""
    print("=" * 80)
    print(" v13.3 Structural Recovery 過濾器測試")
    print("=" * 80)
    print()
    
    print("[Step 1] 套用 v13.3 過濾器...")
    our_records = apply_v133_filter('tree_project/project_code/frontend/ble_debug_log.txt')
    print(f"  重建: {len(our_records)} 個唯一 ID")
    print()
    
    print("[Step 2] 讀取官方輸出...")
    official_records = {}
    with open('tree_project/Tree_app_equipment_info/DATA_2.CSV', 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    official_records[id_clean] = line
    
    print(f"  官方: {len(official_records)} 個唯一 ID")
    print()
    
    # 檢查之前「丟失」的 ID
    print("[Step 3] 檢查之前丟失的 ID 是否恢復...")
    lost_ids = ['10076', '10087', '10221', '10223']
    
    recovered_count = 0
    for lost_id in lost_ids:
        if lost_id in our_records:
            print(f"  ID {lost_id}: RECOVERED!")
            recovered_count += 1
        else:
            print(f"  ID {lost_id}: 仍然丟失")
    
    print(f"\n  恢復: {recovered_count}/{len(lost_ids)}")
    print()
    
    # 比對
    print("[Step 4] 完整比對...")
    print("=" * 80)
    
    matches = 0
    differences = []
    
    for id_val in sorted(official_records.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val in our_records:
            if our_records[id_val] == official_records[id_val]:
                matches += 1
            else:
                differences.append({
                    'id': id_val,
                    'ours': our_records[id_val],
                    'official': official_records[id_val]
                })
        else:
            differences.append({
                'id': id_val,
                'ours': '[MISSING]',
                'official': official_records[id_val]
            })
    
    total = len(official_records)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print(f"\n準確率: {matches}/{total} 個唯一 ID ({accuracy:.1f}%)")
    print(f"改善: +{accuracy - 96.7:.1f}% (從 v13.2 的 96.7% 提升)")
    print()
    
    print(f"差異分類：")
    missing_count = sum(1 for d in differences if d['ours'] == '[MISSING]')
    different_count = len(differences) - missing_count
    
    print(f"  缺失的 ID: {missing_count} 個")
    print(f"  有差異的 ID: {different_count} 個")
    print()
    
    if differences and different_count > 0:
        print(f"剩餘差異 (前 10 筆):")
        print("-" * 80)
        
        shown = 0
        for diff in differences:
            if diff['ours'] != '[MISSING]' and shown < 10:
                print(f"\nID: {diff['id']}")
                
                ours_fields = diff['ours'].split(';')
                official_fields = diff['official'].split(';')
                
                for idx in range(min(len(ours_fields), len(official_fields))):
                    if ours_fields[idx] != official_fields[idx]:
                        print(f"  欄位[{idx}]: '{ours_fields[idx]}' vs '{official_fields[idx]}'")
                        break
                
                shown += 1
    
    print()
    print("=" * 80)
    
    if accuracy >= 99.5:
        print("\n SUCCESS: 100% 成功！可以發布！")
    elif accuracy >= 98:
        print(f"\n EXCELLENT: 非常接近 ({accuracy:.1f}%)！")
        print("Structural Recovery 有效！")
    elif accuracy >= 96.7:
        print(f"\n GOOD: 有改善 ({accuracy:.1f}%)！")
    else:
        print(f"\n NEUTRAL: 改善不明顯 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy

if __name__ == "__main__":
    test_v133()






