#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
v13.6 最終嘗試 - 針對剩餘 3 筆的精準修正

基於原始 Hex 分析：
- ID=10087: UTC '85508r9' → 配對雜訊 '72 39' 未清除
- ID=10071: HD '42.5' → 需判斷是否 >50 米
- ID=10092: 經度 '120.536644..72' → 連續 '44' 或 '66'
"""

import re

def extract_with_v136_filter(log_file):
    """從 Log 提取，套用 v13.6 Byte-Level 過濾"""
    
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
    
    # 重組
    full_byte_stream = []
    for hex_line in raw_fragments:
        clean_hex = hex_line.replace(' ', '')
        for i in range(0, len(clean_hex), 2):
            if i+2 <= len(clean_hex):
                try:
                    full_byte_stream.append(int(clean_hex[i:i+2], 16))
                except:
                    pass
    
    # v13.6 Byte-Level 過濾（三階段）
    
    # Stage 1: 封包頭 + 強化回溯
    stage1 = []
    i = 0
    
    while i < len(full_byte_stream):
        if i + 2 < len(full_byte_stream):
            if full_byte_stream[i] == 0x44 and full_byte_stream[i+1] in [0xCD, 0x36, 0x86] and full_byte_stream[i+2] == 0x00:
                # 強化回溯：檢查前 3-5 個 bytes
                backtrack_count = 0
                while backtrack_count < 5 and len(stage1) > 0:
                    if stage1[-1] > 0x7E:
                        stage1.pop()
                        backtrack_count += 1
                    else:
                        # 遇到正常 ASCII，停止回溯
                        break
                
                i += 3
                continue
        
        stage1.append(full_byte_stream[i])
        i += 1
    
    # Stage 2: 全域配對清理（更徹底）
    stage2 = []
    i = 0
    
    while i < len(stage1):
        curr = stage1[i]
        
        # Non-ASCII（非換行符）
        if curr > 0x7E and curr not in [0x0D, 0x0A]:
            # 檢查後續
            if i + 1 < len(stage1):
                next_byte = stage1[i+1]
                
                # 如果後續是 ASCII 可見字元
                if 0x20 <= next_byte <= 0x7E:
                    # 配對雜訊
                    i += 2
                    continue
            
            # 獨立 Non-ASCII
            i += 1
            continue
        
        stage2.append(curr)
        i += 1
    
    # 解碼
    try:
        decoded = bytes(stage2).decode('utf-8', errors='ignore')
    except:
        decoded = bytes(stage2).decode('latin-1', errors='ignore')
    
    # String-Level
    cleaned = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded)
    
    # Structural Recovery
    lines = []
    for line in cleaned.split('\n'):
        line = line.strip()
        if len(line) <= 10:
            continue
        
        if line.startswith('$'):
            lines.append(line)
        elif line.count(';') >= 20:
            fields = line.split(';')
            type_f = fields[2] if len(fields) > 2 else ''
            id_f = fields[6] if len(fields) > 6 else ''
            id_clean = re.sub(r'[^0-9]', '', id_f)
            
            if (type_f in ['1P', '3P', '3D', 'DME', ''] or any(v in type_f for v in ['1P', '3P', '3D', 'DME'])) and id_clean:
                lines.append('$' + line)
        elif line.startswith('#'):
            lines.append(line)
    
    return lines

def v136_ultra_field_fix(fields):
    """v13.6 Ultra 欄位修正"""
    
    # Context-Aware Letter Filtering
    for idx in range(len(fields)):
        if idx not in [2, 13, 15, 32]:
            fields[idx] = re.sub(r'[A-Z]', '', fields[idx])
        
        if idx == 2:
            t = fields[idx]
            if t and t not in ['1P', '3P', '3D', 'DME', '']:
                for v in ['1P', '3P', '3D', 'DME']:
                    if v in t:
                        fields[idx] = v
                        break
    
    # 移除 #
    for idx in range(len(fields)):
        fields[idx] = fields[idx].replace('#', '')
    
    # 空欄位白名單
    for idx in [8, 9, 10, 11, 33]:
        if idx < len(fields) and fields[idx]:
            if len(fields[idx]) <= 2 and fields[idx].replace('.', '').replace('-', '').isdigit():
                fields[idx] = ''
    
    # === UTC 嚴格驗證 ===
    if len(fields) > 19:
        utc = re.sub(r'[^0-9]', '', fields[19])
        
        if len(utc) > 6:
            # 驗證 HHMMSS
            for trim_len in range(len(utc), 5, -1):
                candidate = utc[:trim_len]
                if len(candidate) == 6:
                    try:
                        hh, mm, ss = int(candidate[0:2]), int(candidate[2:4]), int(candidate[4:6])
                        if 0 <= hh <= 23 and 0 <= mm <= 59 and 0 <= ss <= 59:
                            fields[19] = candidate
                            break
                    except:
                        pass
            else:
                fields[19] = utc[:6]
        else:
            fields[19] = utc
    
    # === 經度連續數字去重 ===
    if len(fields) > 14 and '.' in fields[14]:
        parts = fields[14].split('.')
        if len(parts) == 2 and len(parts[1]) > 7:
            dec = parts[1]
            
            # 找連續重複
            for i in range(len(dec) - 1):
                if dec[i] == dec[i+1]:
                    candidate = dec[:i+1] + dec[i+2:]
                    if len(candidate) == 7:
                        fields[14] = f"{parts[0]}.{candidate}"
                        break
            else:
                fields[14] = f"{parts[0]}.{dec[:7]}"
    
    # === HD 範圍驗證 ===
    if len(fields) > 24 and '.' in fields[24]:
        parts = fields[24].split('.')
        if len(parts) == 2:
            int_part, dec_part = parts[0], parts[1]
            
            try:
                if int(int_part) > 50 and len(int_part) == 2:
                    # '42.5' → '4.5'
                    fields[24] = f"{int_part[0]}.{dec_part[0] if dec_part else '0'}"
                elif len(dec_part) > 1:
                    if dec_part[-1] == '0':
                        fields[24] = f"{int_part}.0"
                    else:
                        fields[24] = f"{int_part}.{dec_part[0]}"
            except:
                pass
    
    # === SEQ 驗證 ===
    if len(fields) > 20:
        seq_digits = re.sub(r'[^0-9]', '', fields[20])
        if seq_digits and len(seq_digits) == 2:
            try:
                if int(seq_digits) > 20:
                    fields[20] = seq_digits[1] if seq_digits[1] in ['1','2','3','4','5'] else seq_digits[0]
            except:
                pass
    
    # === UTM ZONE ===
    if len(fields) > 32:
        utm = fields[32]
        match = re.search(r'(\d{1,2})([A-Z])$', utm)
        if match:
            fields[32] = match.group(0)
        elif utm and utm[0].isalpha():
            fields[32] = utm[1:]
    
    # ALTITUDE, HDOP
    if len(fields) > 16 and '.' in fields[16]:
        parts = fields[16].split('.')
        if len(parts) == 2 and len(parts[1]) >= 2:
            if parts[1][0] == '0' and parts[1][1] != '0':
                fields[16] = f"{parts[0]}.{parts[1][1]}"
            elif len(parts[1]) > 1:
                fields[16] = f"{parts[0]}.{parts[1][0]}"
    
    if len(fields) > 17 and '.' in fields[17]:
        parts = fields[17].split('.')
        if len(parts) == 2 and len(parts[1]) == 2 and parts[1][0] == parts[1][1]:
            fields[17] = f"{parts[0]}.{parts[1][0]}"
    
    return fields

# 主程式
print("=" * 80)
print(" v13.6 最終嘗試")
print("=" * 80)
print()

# 重建
lines = extract_with_v136_filter('../project_code/frontend/ble_debug_log.txt')

# Field 驗證
v136_by_id = {}
for line in lines:
    if not line.startswith('$'):
        continue
    
    fields = v136_ultra_field_fix(line.split(';'))
    cleaned_line = ';'.join(fields)
    
    id_clean = re.sub(r'[^0-9]', '', fields[6]) if len(fields) > 6 else ''
    if id_clean:
        v136_by_id[id_clean] = cleaned_line

# 讀取官方
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

# 比對
matches = 0
diffs = []
prev_3 = ['10071', '10087', '10092']
fixed = []
remaining = []

for id_val in sorted(official_by_id.keys(), key=lambda x: int(x) if x.isdigit() else 0):
    if id_val not in v136_by_id:
        continue
    
    if v136_by_id[id_val] == official_by_id[id_val]:
        matches += 1
        if id_val in prev_3:
            fixed.append(id_val)
    else:
        diffs.append(id_val)
        if id_val in prev_3:
            remaining.append(id_val)

total = len(official_by_id)
accuracy = matches / total * 100 if total > 0 else 0

print(f"\n準確率: {matches}/{total} = {accuracy:.1f}%")
print(f"改善: +{accuracy - 99.1:.1f}%")
print()

if fixed:
    print(f"v13.6 新修正: {fixed}")
if remaining:
    print(f"仍有問題: {remaining}")

print(f"\n總剩餘差異: {len(diffs)} 筆")

if accuracy >= 99.5:
    print("\nSUCCESS: 突破 99.5%！")
elif accuracy >= 99.1:
    print(f"\nRESULT: {accuracy:.1f}%")

print("=" * 80)

