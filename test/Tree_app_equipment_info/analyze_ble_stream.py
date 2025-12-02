import re
import sys
import os

def analyze_ble_stream(log_path):
    print(f"--- Analyzing BLE Stream: {log_path} ---")
    
    content = ""
    # Try multiple encodings
    for enc in ['utf-8', 'utf-16', 'cp1252', 'latin-1']:
        try:
            with open(log_path, 'r', encoding=enc) as f:
                content = f.read()
            print(f"Successfully read with encoding: {enc}")
            break
        except:
            continue
            
    if not content:
        print("Failed to read file with any encoding.")
        return

    # 1. Extract [BLE RAW] fragments
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    print(f"Found {len(raw_fragments)} BLE fragments")

    # 2. Reassemble fragments
    full_byte_stream = []
    for hex_line in raw_fragments:
        try:
            # Basic cleanup
            clean_hex = hex_line.replace(' ', '')
            # Convert hex pairs to bytes
            bytes_list = []
            for i in range(0, len(clean_hex), 2):
                if i+2 <= len(clean_hex):
                    bytes_list.append(int(clean_hex[i:i+2], 16))
            full_byte_stream.extend(bytes_list)
        except Exception as e:
            pass

    # Decode to string
    try:
        decoded_stream = bytes(full_byte_stream).decode('utf-8', errors='ignore')
    except:
        decoded_stream = str(bytes(full_byte_stream))

    print(f"Reassembled Stream Length: {len(decoded_stream)} chars")

    # 3. Simulate LineSplitter
    # VLGEO uses \r\n (CRLF)
    raw_lines = decoded_stream.replace('\r', '').split('\n')
    
    print(f"Split into {len(raw_lines)} lines")

    valid_data_count = 0
    noise_lines = 0
    header_lines = 0
    incomplete_lines = 0
    
    print("\n--- Analysis Report ---")

    for line in raw_lines:
        line = line.strip()
        # Simulate BleDataProcessor cleaning
        line = re.sub(r'[^\x20-\x7E]', '', line) 
        
        if not line: continue

        # Logic from v13.1 BleDataProcessor
        is_valid = True
        rejection_reason = ""

        if not line.startswith('$'):
            is_valid = False
            if line.startswith('MARK') or line.startswith('#'):
                rejection_reason = "Header/Setting"
                header_lines += 1
            else:
                rejection_reason = "Noise"
                noise_lines += 1
        elif ';' not in line:
            is_valid = False
            rejection_reason = "Format Error"
            noise_lines += 1
        else:
            parts = line.split(';')
            # Check basic length (ID is at index 6)
            if len(parts) <= 6:
                is_valid = False
                rejection_reason = "Incomplete"
                incomplete_lines += 1
            else:
                # Check GPS (Index 12, 14)
                try:
                    # Index 12 is LAT, 14 is LON
                    if len(parts) > 14:
                        lat = parts[12].strip()
                        lon = parts[14].strip()
                        if not lat or not lon:
                            is_valid = False
                            rejection_reason = "Missing GPS"
                            incomplete_lines += 1
                            # Extract ID for report
                            rec_id = parts[6]
                            print(f"[DROP] ID: {rec_id.ljust(5)} -> {rejection_reason}")
                    else:
                        is_valid = False
                        rejection_reason = "Truncated Line"
                        incomplete_lines += 1
                except:
                    is_valid = False
                    rejection_reason = "Parse Error"
                    incomplete_lines += 1

        if is_valid:
            valid_data_count += 1

    print("-" * 30)
    print(f"Summary:")
    print(f"  - Valid Data  : {valid_data_count}")
    print(f"  - Noise       : {noise_lines}")
    print(f"  - Header/Set  : {header_lines}")
    print(f"  - Incomplete  : {incomplete_lines} (Missing GPS/ID)")
    print("-" * 30)

if __name__ == "__main__":
    log_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    if len(sys.argv) > 1:
        log_file = sys.argv[1]
    analyze_ble_stream(log_file)
