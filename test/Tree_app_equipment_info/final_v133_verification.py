#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
v13.3 最終驗證腳本
完整套用所有過濾器，輸出詳細分析報告
"""

import re
import json

def apply_full_v133_pipeline(log_file):
    """完整的 v13.3 處理流程"""
    
    # ===== 階段 1: 提取原始數據 =====
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
    
    print(f"[提取] BLE fragments: {len(raw_fragments)}")
    
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
    
    print(f"[重組] 原始 byte stream: {len(full_byte_stream)} bytes")
    
    # ===== 階段 2: Byte-Level 三階段過濾 =====
    
    # Stage 2.1: 封包頭 + 回溯
    cleaned_stage1 = []
    i = 0
    removed_headers = 0
    
    while i < len(full_byte_stream):
        is_header = False
        if i + 2 < len(full_byte_stream):
            if (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0xCD and full_byte_stream[i+2] == 0x00) or \
               (full_byte_stream[i] == 0x44 and full_byte_stream[i+1] == 0x36 and full_byte_stream[i+2] == 0x00):
                is_header = True
                removed_headers += 1
                
                # 回溯清理
                if len(cleaned_stage1) >= 2 and (cleaned_stage1[-1] > 0x7E or cleaned_stage1[-2] > 0x7E):
                    cleaned_stage1.pop()
                    cleaned_stage1.pop()
                elif len(cleaned_stage1) == 1 and cleaned_stage1[-1] > 0x7E:
                    cleaned_stage1.pop()
                
                i += 3
                continue
        
        cleaned_stage1.append(full_byte_stream[i])
        i += 1
    
    print(f"[Byte-Level 2.1] 移除封包頭: {removed_headers} 個")
    
    # Stage 2.2: 全域配對清理
    cleaned_stage2 = []
    i = 0
    removed_pairs = 0
    
    while i < len(cleaned_stage1):
        if i + 1 < len(cleaned_stage1):
            current_byte = cleaned_stage1[i]
            next_byte = cleaned_stage1[i+1]
            
            if current_byte > 0x7E and current_byte not in [0x0D, 0x0A]:
                if 0x20 <= next_byte <= 0x7E:
                    i += 2
                    removed_pairs += 1
                    continue
                else:
                    i += 1
                    continue
        
        if cleaned_stage1[i] > 0x7E and cleaned_stage1[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        cleaned_stage2.append(cleaned_stage1[i])
        i += 1
    
    print(f"[Byte-Level 2.2] 移除配對雜訊: {removed_pairs} 對")
    print(f"[Byte-Level 總計] {len(full_byte_stream)} → {len(cleaned_stage2)} bytes (移除 {len(full_byte_stream)-len(cleaned_stage2)})")
    print()
    
    # ===== 階段 3: 解碼 =====
    try:
        decoded_text = bytes(cleaned_stage2).decode('utf-8', errors='ignore')
    except:
        decoded_text = bytes(cleaned_stage2).decode('latin-1', errors='ignore')
    
    print(f"[解碼] {len(decoded_text)} 字元")
    
    # ===== 階段 4: String-Level 白名單 =====
    cleaned_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_text)
    print(f"[String-Level] {len(cleaned_text)} 字元")
    print()
    
    # ===== 階段 5: Structural Recovery + Field-Specific =====
    print("[Structural Recovery + Field-Specific]...")
    
    recovered_lines = []
    recovery_count = 0
    
    for line in cleaned_text.split('\n'):
        line = line.strip()
        
        if len(line) <= 10:
            continue
        
        # 正常的 $ 開頭
        if line.startswith('$'):
            recovered_lines.append(line)
            continue
        
        # 智能結構匹配
        if line.count(';') >= 20:
            fields = line.split(';')
            
            type_field = fields[2] if len(fields) > 2 else ''
            id_field = fields[6] if len(fields) > 6 else ''
            id_clean = re.sub(r'[^0-9]', '', id_field)
            
            if (type_field in ['1P', '3P', '3D', 'DME', ''] or \
                any(vt in type_field for vt in ['1P', '3P', '3D', 'DME'])) and \
               id_clean and len(id_clean) >= 1:
                
                recovered_line = '$' + line
                recovered_lines.append(recovered_line)
                recovery_count += 1
                continue
        
        # Header
        if line.startswith('#'):
            recovered_lines.append(line)
    
    print(f"  恢復缺少 $ 的記錄: {recovery_count} 筆")
    
    # Field-Specific 清理
    cleaned_lines = []
    
    for line in recovered_lines:
        if not line.startswith('$'):
            cleaned_lines.append(line)
            continue
        
        fields = line.split(';')
        
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
        
        cleaned_lines.append(';'.join(fields))
    
    print(f"  Field-Specific 清理完成")
    print()
    
    # ===== 階段 6: Last Record Wins =====
    id_records = {}
    
    for line in cleaned_lines:
        if not line.startswith('$'):
            continue
        
        fields = line.split(';')
        if len(fields) > 6:
            id_clean = re.sub(r'[^0-9]', '', fields[6])
            if id_clean:
                id_records[id_clean] = line
    
    print(f"[Last Record Wins] 最終: {len(id_records)} 個唯一 ID")
    print()
    
    return id_records

def compare_with_official(our_records, official_file):
    """與官方輸出詳細比對"""
    
    official_records = {}
    with open(official_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('$'):
                continue
            
            fields = line.split(';')
            if len(fields) > 6:
                id_clean = re.sub(r'[^0-9]', '', fields[6])
                if id_clean:
                    official_records[id_clean] = line
    
    print("=" * 80)
    print(" 詳細比對結果")
    print("=" * 80)
    print()
    
    matches = 0
    field_differences = []
    missing_ids = []
    
    for id_val in sorted(official_records.keys(), key=lambda x: int(x) if x.isdigit() else 0):
        if id_val not in our_records:
            missing_ids.append(id_val)
            continue
        
        if our_records[id_val] == official_records[id_val]:
            matches += 1
        else:
            # 欄位級別比對
            ours_fields = our_records[id_val].split(';')
            official_fields = official_records[id_val].split(';')
            
            for idx in range(min(len(ours_fields), len(official_fields))):
                if ours_fields[idx] != official_fields[idx]:
                    field_differences.append({
                        'id': id_val,
                        'field': idx,
                        'ours': ours_fields[idx],
                        'official': official_fields[idx]
                    })
    
    total = len(official_records)
    accuracy = matches / total * 100 if total > 0 else 0
    
    print(f"準確率: {matches}/{total} = {accuracy:.1f}%")
    print()
    
    if missing_ids:
        print(f"缺失的 ID ({len(missing_ids)} 個):")
        print(f"  {missing_ids}")
        print()
    
    if field_differences:
        print(f"欄位差異 (共 {len(field_differences)} 個，顯示前 20 個):")
        print("-" * 80)
        
        for i, diff in enumerate(field_differences[:20], 1):
            print(f"{i}. ID={diff['id']}, 欄位[{diff['field']}]: '{diff['ours']}' vs '{diff['official']}'")
        
        if len(field_differences) > 20:
            print(f"... 還有 {len(field_differences) - 20} 個")
    
    print()
    print("=" * 80)
    
    # 儲存詳細報告
    report = {
        'accuracy': accuracy,
        'total': total,
        'matches': matches,
        'missing_ids': missing_ids,
        'field_differences': field_differences
    }
    
    with open('tree_project/Tree_app_equipment_info/V133_VERIFICATION_REPORT.json', 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print("\n詳細報告已儲存至: V133_VERIFICATION_REPORT.json")
    print()
    
    return accuracy

def main():
    """主程式"""
    print("\n")
    print("=" * 80)
    print(" v13.3 最終驗證 - 完整流程測試")
    print("=" * 80)
    print()
    
    log_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    official_file = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    # 1. 套用完整過濾流程
    our_records = apply_full_v133_pipeline(log_file)
    
    # 2. 與官方比對
    accuracy = compare_with_official(our_records, official_file)
    
    # 3. 結論
    print("=" * 80)
    print(" 最終結論")
    print("=" * 80)
    print()
    
    print("v13.3 過濾器架構：")
    print("  1. Byte-Level (兩階段)")
    print("     - Stage 1: 封包頭 + 回溯配對清理")
    print("     - Stage 2: 全域配對雜訊清理 (Non-ASCII + ASCII)")
    print("  2. String-Level 白名單")
    print("  3. Structural Recovery (智能辨識缺少 $ 的記錄)")
    print("  4. Field-Specific (Context-Aware Letter Filtering)")
    print("  5. Last Record Wins (去重)")
    print()
    
    print(f"最終準確率: {accuracy:.1f}%")
    print()
    
    if accuracy >= 99.5:
        print("STATUS: 成功達到 100% 官方 App 水準！")
    elif accuracy >= 98:
        print("STATUS: 非常接近官方 App！")
    elif accuracy >= 95:
        print("STATUS: 優於業界基準 (38.4%)，接近完美！")
    elif accuracy >= 90:
        print("STATUS: 顯著優於業界基準！")
    else:
        print("STATUS: 需要進一步優化")
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    main()






