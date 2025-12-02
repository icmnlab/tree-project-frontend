import re
import sys
import os

def extract_csv_from_log(log_path):
    """從 BLE Log 中提取並重組 CSV 字串流"""
    content = ""
    # Try multiple encodings
    for enc in ['utf-8', 'utf-16', 'cp1252', 'latin-1']:
        try:
            with open(log_path, 'r', encoding=enc) as f:
                content = f.read()
            print(f"[OK] Log read successfully (encoding: {enc})")
            break
        except:
            continue
            
    if not content:
        print("[ERROR] Failed to read Log file")
        return ""

    # 1. Extract [BLE RAW] fragments
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    print(f"[OK] Found {len(raw_fragments)} BLE Hex fragments")

    # 2. Reassemble byte stream (模擬前端接收)
    full_byte_stream = []
    for hex_line in raw_fragments:
        try:
            clean_hex = hex_line.replace(' ', '')
            bytes_list = []
            for i in range(0, len(clean_hex), 2):
                if i+2 <= len(clean_hex):
                    bytes_list.append(int(clean_hex[i:i+2], 16))
            full_byte_stream.extend(bytes_list)
        except:
            pass

    print(f"[OK] Raw byte stream: {len(full_byte_stream)} bytes")

    # 2.5. [v13.1 FINAL] Byte-Level PacketLogger Filter (回溯式清理)
    # 基於 serial log 的完整分析，模式為：
    #   [正常數據] + [2-byte 雜訊對] + [44 CD 00] + [正常數據]
    # 策略：偵測封包頭時，回溯移除前面的雜訊對
    cleaned_bytes = []
    i = 0
    while i < len(full_byte_stream):
        # 偵測封包頭
        is_header = False
        header_len = 0
        
        if (i + 2 < len(full_byte_stream) and
            full_byte_stream[i] == 0x44 and
            full_byte_stream[i+1] == 0xCD and
            full_byte_stream[i+2] == 0x00):
            is_header = True
            header_len = 3
        elif (i + 2 < len(full_byte_stream) and
            full_byte_stream[i] == 0x44 and
            full_byte_stream[i+1] == 0x36 and
            full_byte_stream[i+2] == 0x00):
            is_header = True
            header_len = 3
        
        if is_header:
            # 回溯清理：移除前面可能的雜訊對
            if len(cleaned_bytes) >= 2:
                if cleaned_bytes[-1] > 0x7E or cleaned_bytes[-2] > 0x7E:
                    cleaned_bytes.pop()
                    cleaned_bytes.pop()
            elif len(cleaned_bytes) == 1 and cleaned_bytes[-1] > 0x7E:
                cleaned_bytes.pop()
            
            i += header_len
            continue
        
        # 獨立的 Non-ASCII byte
        if full_byte_stream[i] > 0x7E and full_byte_stream[i] != 0x0D and full_byte_stream[i] != 0x0A:
            i += 1
            continue
        
        # EOT 訊號
        if (i + 2 < len(full_byte_stream) and
            full_byte_stream[i] == 0x5A and
            full_byte_stream[i+1] == 0xBF and
            full_byte_stream[i+2] == 0xFB):
            i += 3
            continue
        
        cleaned_bytes.append(full_byte_stream[i])
        i += 1

    removed_count = len(full_byte_stream) - len(cleaned_bytes)
    print(f"[OK] After PacketLogger filter: {len(cleaned_bytes)} bytes (removed {removed_count})")

    # 3. Decode to string (模擬 UTF-8 解碼)
    try:
        decoded_stream = bytes(cleaned_bytes).decode('utf-8', errors='ignore')
    except:
        decoded_stream = bytes(cleaned_bytes).decode('latin-1')

    print(f"[OK] Decoded stream: {len(decoded_stream)} chars")
    
    # 4. 模擬前端字串級白名單過濾 (v13.1 Final)
    # 只保留: 0-9, A-Z, . ; - $ # \r \n
    cleaned = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded_stream)
    
    print(f"[OK] After final whitelist: {len(cleaned)} chars")
    
    # 5. 將重建的 CSV 寫入檔案供檢查
    output_path = os.path.join(os.path.dirname(log_path), '../Tree_app_equipment_info/reconstructed_from_log_v13.1.csv')
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(cleaned)
        print(f"[OK] Saved reconstructed CSV to: reconstructed_from_log_v13.1.csv")
    except:
        pass
    
    return cleaned

def parse_csv_to_dict(csv_content):
    """將 CSV 內容解析為 Map<ID, FullLine>"""
    records = {}
    
    for line in csv_content.splitlines():
        line = line.strip()
        if not line: continue
        
        # 模擬前端過濾：只接受 $ 開頭
        if not line.startswith('$'): continue
        if ';' not in line: continue
        
        parts = line.split(';')
        if len(parts) <= 6: continue
        
        rec_id = parts[6].strip()
        if rec_id:
            # 使用 ID 為 key，整行為 value
            records[rec_id] = line
    
    return records

def compare_full_data(log_path, ground_truth_path):
    print("=" * 60)
    print(" VLGEO Data Verification - Full Field Comparison")
    print("=" * 60)
    
    # Step 1: 從 Log 重建 CSV
    print("\n[Step 1] Reconstructing CSV from BLE Log...")
    reconstructed_csv = extract_csv_from_log(log_path)
    
    # Step 2: 解析兩份 CSV
    print("\n[Step 2] Parsing both CSVs...")
    log_records = parse_csv_to_dict(reconstructed_csv)
    
    with open(ground_truth_path, 'r', encoding='utf-8') as f:
        gt_csv = f.read()
    gt_records = parse_csv_to_dict(gt_csv)
    
    print(f"[OK] Log reconstructed: {len(log_records)} records")
    print(f"[OK] Ground Truth: {len(gt_records)} records")
    
    # Step 3: 全欄位比對
    print("\n[Step 3] Field-by-field comparison...")
    print("-" * 60)
    
    mismatches = []
    missing_in_log = []
    extra_in_log = []
    
    # 檢查 Ground Truth 中的每一筆
    for rec_id, gt_line in gt_records.items():
        if rec_id in log_records:
            log_line = log_records[rec_id]
            
            # 逐欄位比對
            gt_fields = gt_line.split(';')
            log_fields = log_line.split(';')
            
            # 檢查每個欄位
            field_diffs = []
            max_len = max(len(gt_fields), len(log_fields))
            
            for i in range(max_len):
                gt_val = gt_fields[i].strip() if i < len(gt_fields) else ""
                log_val = log_fields[i].strip() if i < len(log_fields) else ""
                
                if gt_val != log_val:
                    field_diffs.append(f"  欄位[{i}]: GT='{gt_val}' vs LOG='{log_val}'")
            
            if field_diffs:
                mismatches.append({
                    'id': rec_id,
                    'diffs': field_diffs
                })
        else:
            missing_in_log.append(rec_id)
    
    # 檢查 Log 中多出來的
    for rec_id in log_records:
        if rec_id not in gt_records:
            extra_in_log.append(rec_id)
    
    # Step 4: 輸出報告
    print("\n[Step 4] Verification Results")
    print("=" * 60)
    
    if not mismatches and not missing_in_log and not extra_in_log:
        print("[SUCCESS] Log data matches Ground Truth 100%!")
    else:
        if mismatches:
            print(f"[WARNING] {len(mismatches)} records have field differences:")
            for m in mismatches[:10]:  # 只顯示前 10 筆
                print(f"\n  ID: {m['id']}")
                for diff in m['diffs'][:5]:  # 每筆最多顯示 5 個差異欄位
                    print(diff)
        
        if missing_in_log:
            print(f"\n[WARNING] {len(missing_in_log)} records missing in Log:")
            print(f"  IDs: {', '.join(missing_in_log[:20])}")
        
        if extra_in_log:
            print(f"\n[WARNING] {len(extra_in_log)} extra records in Log:")
            print(f"  IDs: {', '.join(extra_in_log[:20])}")
    
    print("=" * 60)

if __name__ == "__main__":
    log_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    gt_file = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    if len(sys.argv) > 2:
        log_file = sys.argv[1]
        gt_file = sys.argv[2]
    
    compare_full_data(log_file, gt_file)

