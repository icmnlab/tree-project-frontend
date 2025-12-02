#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
深度追蹤剩餘 3 筆差異的原始 Hex 數據
找出數字重複/錯誤的確切原因

目標 ID:
- 10071: HD '42.5' vs '4.5'
- 10087: UTC '855089' vs '85508'  
- 10092: 經度 '120.53664472' vs '120.5366472'
"""

import re

def find_id_in_log_with_context(log_file, target_id):
    """
    在 Log 中找到目標 ID 的所有 fragments
    並提供前後文
    """
    
    # ID 的 Hex（例如 "10087" = 31 30 30 38 37）
    id_hex_str = ''.join([f"{ord(c):02X}" for c in target_id])
    
    with open(log_file, 'r', encoding='utf-16') as f:
        content = f.read()
    
    # 提取所有 [BLE RAW] fragments
    all_fragments = []
    for line_num, line in enumerate(content.splitlines(), 1):
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                all_fragments.append({
                    'line_num': line_num,
                    'hex': hex_str
                })
    
    # 找到包含目標 ID 的 fragment
    matching_indices = []
    
    for idx, frag in enumerate(all_fragments):
        hex_no_space = frag['hex'].replace(' ', '')
        if id_hex_str in hex_no_space:
            matching_indices.append(idx)
    
    return all_fragments, matching_indices

def reconstruct_full_record(all_fragments, start_index):
    """
    從包含 ID 的 fragment 開始，向後重建完整記錄
    直到遇到換行符 (0x0D 0x0A)
    """
    
    full_bytes = []
    
    # 從 start_index 開始，收集最多 15 個 fragments
    for i in range(start_index, min(start_index + 15, len(all_fragments))):
        hex_str = all_fragments[i]['hex'].replace(' ', '')
        
        # 轉換為 bytes
        for j in range(0, len(hex_str), 2):
            if j + 2 <= len(hex_str):
                try:
                    byte_val = int(hex_str[j:j+2], 16)
                    full_bytes.append(byte_val)
                    
                    # 檢查是否遇到換行
                    if len(full_bytes) >= 2 and full_bytes[-2] == 0x0D and full_bytes[-1] == 0x0A:
                        # 找到完整記錄的結尾
                        return full_bytes
                except ValueError:
                    pass
    
    return full_bytes

def analyze_id_in_detail(log_file, target_id, field_name, field_index):
    """詳細分析目標 ID 的特定欄位"""
    
    print("=" * 80)
    print(f" 深度分析 ID={target_id} 的 {field_name} 欄位 (field[{field_index}])")
    print("=" * 80)
    print()
    
    # 1. 找到 ID 在 Log 中的位置
    all_fragments, matching_indices = find_id_in_log_with_context(log_file, target_id)
    
    if not matching_indices:
        print(f"未在 Log 中找到 ID={target_id}！")
        return
    
    print(f"找到 {len(matching_indices)} 個包含 ID={target_id} 的 fragments")
    print()
    
    # 2. 重建完整記錄
    for idx_num, frag_idx in enumerate(matching_indices[:3], 1):
        print(f"### Fragment {idx_num} (Log Line {all_fragments[frag_idx]['line_num']})")
        print("-" * 80)
        
        full_bytes = reconstruct_full_record(all_fragments, frag_idx)
        
        print(f"完整記錄長度: {len(full_bytes)} bytes")
        print()
        
        # 顯示原始 Hex（每 20 bytes 一行）
        print("原始 Hex:")
        for i in range(0, min(len(full_bytes), 200), 20):
            hex_line = ' '.join([f"{b:02X}" for b in full_bytes[i:i+20]])
            ascii_line = ''.join([chr(b) if 32 <= b <= 126 else '.' for b in full_bytes[i:i+20]])
            print(f"  {i:04d}: {hex_line:60s} {ascii_line}")
        print()
        
        # 3. 解碼並顯示
        try:
            decoded = bytes(full_bytes).decode('utf-8', errors='ignore')
        except:
            decoded = bytes(full_bytes).decode('latin-1', errors='ignore')
        
        print("解碼結果:")
        print(f"  {decoded[:200]}")
        print()
        
        # 4. 提取目標欄位
        # 先清理（模擬我們的過濾器）
        cleaned_bytes = full_bytes.copy()
        
        # 移除 PacketLogger 封包頭及配對雜訊
        temp_cleaned = []
        i = 0
        while i < len(cleaned_bytes):
            # 封包頭檢測
            is_header = False
            if i + 2 < len(cleaned_bytes):
                if (cleaned_bytes[i] == 0x44 and cleaned_bytes[i+1] in [0xCD, 0x36, 0x86] and cleaned_bytes[i+2] == 0x00):
                    is_header = True
                    
                    # 回溯清理
                    if len(temp_cleaned) >= 2 and (temp_cleaned[-1] > 0x7E or temp_cleaned[-2] > 0x7E):
                        temp_cleaned.pop()
                        temp_cleaned.pop()
                    elif len(temp_cleaned) == 1 and temp_cleaned[-1] > 0x7E:
                        temp_cleaned.pop()
                    
                    i += 3
                    continue
            
            temp_cleaned.append(cleaned_bytes[i])
            i += 1
        
        # 全域配對清理
        final_cleaned = []
        i = 0
        while i < len(temp_cleaned):
            if i + 1 < len(temp_cleaned):
                if temp_cleaned[i] > 0x7E and temp_cleaned[i] not in [0x0D, 0x0A]:
                    if 0x20 <= temp_cleaned[i+1] <= 0x7E:
                        i += 2  # 配對雜訊
                        continue
                    else:
                        i += 1
                        continue
            
            if temp_cleaned[i] > 0x7E and temp_cleaned[i] not in [0x0D, 0x0A]:
                i += 1
                continue
            
            final_cleaned.append(temp_cleaned[i])
            i += 1
        
        # 解碼清洗後的數據
        try:
            cleaned_decoded = bytes(final_cleaned).decode('utf-8', errors='ignore')
        except:
            cleaned_decoded = bytes(final_cleaned).decode('latin-1', errors='ignore')
        
        cleaned_decoded = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', cleaned_decoded)
        
        print("清洗後:")
        print(f"  {cleaned_decoded[:200]}")
        print()
        
        # 提取欄位
        csv_line = cleaned_decoded.strip()
        if not csv_line.startswith('$'):
            if csv_line.count(';') >= 20:
                csv_line = '$' + csv_line
        
        fields = csv_line.split(';')
        
        if len(fields) > field_index:
            target_field_value = fields[field_index]
            print(f"{field_name} 欄位 (field[{field_index}]): '{target_field_value}'")
            print()
            
            # 分析這個值
            print("分析:")
            
            if field_name == "HD" and target_field_value == '42.5':
                print("  問題: '42.5' 應該是 '4.5'")
                print("  推測: '42' = '4' + 重複的 '2'，或者真的是 42.5 米")
                print("  策略: 檢查前後文，看是否有其他 HD 值作為參考")
            
            elif field_name == "UTC" and '855089' in target_field_value:
                print("  問題: '855089' 應該是 '85508'")
                print("  推測: '9' 在末尾被重複了")
                print("  驗證: HHMMSS 格式，85508 = 08:55:08（合法），855089 = 85:50:89（不合法）")
                print("  → 明確應該去掉最後的 '9'")
            
            elif field_name == "LON" and '3664472' in target_field_value:
                print("  問題: 小數部分 '53664472' 應該是 '5366472'")
                print("  推測: 某個 '4' 或 '6' 被重複")
                print("  → 需要找出重複的位置")
                
                # 分析連續數字
                decimal = target_field_value.split('.')[1] if '.' in target_field_value else ''
                print(f"  小數部分: '{decimal}'")
                
                for i in range(len(decimal) - 1):
                    if decimal[i] == decimal[i+1]:
                        print(f"  → 位置 {i}-{i+1}: '{decimal[i]}' 連續出現")
        
        print()
        print("-" * 80)
        print()

def main():
    """主程式"""
    
    print("\n")
    print("=" * 80)
    print(" 剩餘 3 筆差異的原始 Hex 深度追蹤")
    print("=" * 80)
    print()
    
    log_file = '../project_code/frontend/ble_debug_log.txt'
    
    # 追蹤每個問題 ID
    analyze_id_in_detail(log_file, '10071', 'HD', 24)
    analyze_id_in_detail(log_file, '10087', 'UTC', 19)
    analyze_id_in_detail(log_file, '10092', 'LON', 14)
    
    print("=" * 80)
    print(" 分析總結")
    print("=" * 80)
    print()
    print("基於原始 Hex 分析：")
    print()
    print("1. ID=10087 (UTC '855089' vs '85508'):")
    print("   → 明確是數字重複，應該去掉最後的 '9'")
    print("   → 可以用 HHMMSS 格式驗證來修正")
    print()
    print("2. ID=10071 (HD '42.5' vs '4.5'):")
    print("   → 需要檢查原始 Hex，判斷是 '4''2' 還是 '42'")
    print("   → 可能需要上下文驗證（HD 通常 <50 米）")
    print()
    print("3. ID=10092 (經度 '120.53664472' vs '120.5366472'):")
    print("   → 小數第7位不同（'4' vs '6'）")
    print("   → 這可能是真實數據差異，難以靠過濾器修正")
    print()
    print("=" * 80)

if __name__ == "__main__":
    main()






