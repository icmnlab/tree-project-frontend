
import re
import sys

def parse_flutter_logs(log_content):
    raw_hex_lines = []
    
    # Iterate through lines and find ones containing "[BLE RAW]"
    for line in log_content.splitlines():
        if "[BLE RAW]" in line:
            # Extract everything after "[BLE RAW]"
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_hex_lines.append(hex_str)

    print(f"DEBUG: Found {len(raw_hex_lines)} raw hex lines.")

    full_byte_stream = []
    for hex_line in raw_hex_lines:
        try:
            cleaned_hex = hex_line.strip()
            if not cleaned_hex: continue
            if not re.match(r'^[0-9A-Fa-f\s]+$', cleaned_hex):
                continue
                
            bytes_list = [int(b, 16) for b in cleaned_hex.split()]
        except ValueError:
            continue
        
        # Simulate the PacketLogger noise filter logic implemented in Dart
        clean_bytes = []
        i = 0
        while i < len(bytes_list):
            # Filter: 0x44 0xCD 0x00 OR 0x44 0x36 0x00
            if i + 2 < len(bytes_list) and \
               bytes_list[i] == 0x44 and \
               (bytes_list[i+1] == 0xCD or bytes_list[i+1] == 0x36) and \
               bytes_list[i+2] == 0x00:
                i += 3
                continue
            
            # Filter EOT: 0x5A 0xBF 0xFB
            if i + 2 < len(bytes_list) and \
               bytes_list[i] == 0x5A and \
               bytes_list[i+1] == 0xBF and \
               bytes_list[i+2] == 0xFB:
                i += 3
                continue

            clean_bytes.append(bytes_list[i])
            i += 1
            
        full_byte_stream.extend(clean_bytes)

    print(f"DEBUG: Total bytes extracted: {len(full_byte_stream)}")

    try:
        decoded_str = bytes(full_byte_stream).decode('utf-8')
    except UnicodeDecodeError:
        decoded_str = bytes(full_byte_stream).decode('latin-1')

    # [FIX] Match the strict allowlist filtering in BleImportPage.dart
    decoded_str = re.sub(r'[^0-9A-Z\.\;\-\r\n]', '', decoded_str)

    return decoded_str

def parse_csv_to_preview_format(csv_content):
    """
    Parses CSV content into a list of record strings.
    Returns a LIST of raw formatted strings (including duplicates).
    Format: "ID: xxx | H: xxx | HD: xxx"
    """
    results = []
    _idxId = 6
    _idxHD = 24
    _idxH = 25
    
    for line in csv_content.splitlines():
        line = line.strip()
        line = re.sub(r'[^\x20-\x7E]', '', line)
        
        if not line or line.startswith('MARK') or line.startswith('#') or 'DATA.CSV' in line:
            continue
        
        if ';' not in line:
            continue
            
        fields = line.split(';')
        if len(fields) <= _idxH:
            continue
            
        try:
            id_val = re.sub(r'[^0-9]', '', fields[_idxId].strip())
            if not id_val: continue
            
            h_val = fields[_idxH].strip()
            height = h_val if h_val else '0.0'
            
            hd_str = ''
            if len(fields) > _idxHD:
                val = fields[_idxHD].strip()
                if val:
                    hd_str = f' | HD: {val}m'
            
            results.append(f'ID: {id_val} | H: {height}m{hd_str}')
        except:
            pass
            
    return results

def deduplicate_records(record_list):
    """
    Applies 'Last Record Wins' logic.
    Input: List of strings "ID: 123 | ..."
    Output: List of strings, unique by ID, keeping the last occurrence.
    """
    unique_map = {}
    no_id_list = [] # Should not happen given parse logic, but for safety

    for record in record_list:
        # Extract ID
        match = re.match(r'ID:\s*(\d+)', record)
        if match:
            rec_id = match.group(1)
            unique_map[rec_id] = record # Overwrite implies Last Record Wins
        else:
            no_id_list.append(record)
    
    # Return sorted by ID for easier reading, though dictionary order is insertion order in newer Py
    # We'll return values. 
    # To match Ground Truth order, we might need better logic, but simple list is fine for set comparison.
    return list(unique_map.values()) + no_id_list

def compare_logs(flutter_log_path, ground_truth_path):
    # 1. Read and Parse Log
    content = ""
    try:
        with open(flutter_log_path, 'r', encoding='utf-16') as f:
            content = f.read()
    except:
        try:
            with open(flutter_log_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except:
             with open(flutter_log_path, 'r', encoding='cp1252', errors='ignore') as f:
                content = f.read()

    reconstructed_csv = parse_flutter_logs(content)
    log_records_raw = parse_csv_to_preview_format(reconstructed_csv)
    
    # Apply Deduplication to Logs
    log_records_clean = deduplicate_records(log_records_raw)

    # 2. Read Ground Truth
    with open(ground_truth_path, 'r', encoding='utf-8') as f:
        ground_truth_lines_raw = [l.strip() for l in f.readlines() if l.strip()]

    # Apply Deduplication to Ground Truth (to ensure apples-to-apples comparison)
    # Because the raw data file might also contain duplicates (re-measurements)
    gt_records_clean = deduplicate_records(ground_truth_lines_raw)

    print(f"\n--- Summary ---")
    print(f"Log Raw Records: {len(log_records_raw)}")
    print(f"Log Unique Records (App Logic): {len(log_records_clean)}")
    print(f"Ground Truth Raw Records: {len(ground_truth_lines_raw)}")
    print(f"Ground Truth Unique Records: {len(gt_records_clean)}")
    
    # 3. Compare
    mismatches = []
    
    # Create maps for O(1) lookup
    # Key = ID, Value = Full String
    def to_map(records):
        m = {}
        for r in records:
            match = re.match(r'ID:\s*(\d+)', r)
            if match:
                m[match.group(1)] = r
        return m

    log_map = to_map(log_records_clean)
    gt_map = to_map(gt_records_clean)

    # Check for data in Log that mismatches GT
    for rid, log_val in log_map.items():
        if rid in gt_map:
            if log_val != gt_map[rid]:
                mismatches.append(f"[VALUE MISMATCH] ID: {rid}\n  Log: {log_val}\n  GT : {gt_map[rid]}")
        else:
            mismatches.append(f"[EXTRA IN LOG] ID: {rid} -> {log_val}")

    # Check for data in GT missing from Log
    for rid, gt_val in gt_map.items():
        if rid not in log_map:
            mismatches.append(f"[MISSING IN LOG] ID: {rid} -> {gt_val}")

    print(f"\n--- Comparison Result ---")
    if not mismatches:
        print("SUCCESS: Logs match Ground Truth perfectly (after deduplication)!")
    else:
        print(f"FOUND {len(mismatches)} MISMATCHES:")
        # Sort mismatches by ID number for easier reading
        def get_id(s):
            m = re.search(r'ID:\s*(\d+)', s)
            return int(m.group(1)) if m else 0
        
        mismatches.sort(key=get_id)
        
        for m in mismatches:
            print(m)

if __name__ == '__main__':
    if len(sys.argv) > 2:
        compare_logs(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python compare.py <flutter_log> <ground_truth>")
