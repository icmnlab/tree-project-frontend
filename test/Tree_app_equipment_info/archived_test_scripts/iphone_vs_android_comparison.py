import re
import sys

def extract_iphone_payload(wireshark_txt):
    """從 iPhone Wireshark dump 提取純 ATT Payload"""
    
    with open(wireshark_txt, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    payloads = []
    current_frame = None
    hex_lines = []
    
    for line in lines:
        # 偵測 Frame 開頭
        if line.startswith('Frame'):
            if current_frame and hex_lines:
                # 處理上一個 Frame
                payloads.append({
                    'frame': current_frame,
                    'hex': hex_lines
                })
            # 開始新 Frame
            current_frame = line.split(':')[0].strip()
            hex_lines = []
        
        # 提取 Hex dump 行
        if line.startswith('0000') or line.startswith('0010'):
            # 格式: "0000  03 40 20 1b 00 17 00 04 00 1b 13 00 38 2e 32 ed   .@ .........8.2."
            parts = line.split()
            if len(parts) > 1:
                # 跳過第一個 (offset) 和最後一個 (ASCII)
                hex_bytes = []
                for i in range(1, len(parts)):
                    if len(parts[i]) == 2:  # Valid hex
                        try:
                            hex_bytes.append(int(parts[i], 16))
                        except:
                            break
                hex_lines.extend(hex_bytes)
    
    # 處理最後一個 Frame
    if current_frame and hex_lines:
        payloads.append({
            'frame': current_frame,
            'hex': hex_lines
        })
    
    print(f"[OK] Extracted {len(payloads)} frames from iPhone capture\n")
    
    # 提取純 ATT Payload (1b 13 00 後面的數據)
    pure_data = []
    for p in payloads:
        hex_data = p['hex']
        # 找到 1b 13 00 的位置
        for i in range(len(hex_data) - 2):
            if hex_data[i] == 0x1b and hex_data[i+1] == 0x13 and hex_data[i+2] == 0x00:
                # ATT Payload 在後面
                payload = hex_data[i+3:]
                pure_data.extend(payload)
                break
    
    print(f"[OK] Pure ATT Payload: {len(pure_data)} bytes")
    
    # 解碼為字串
    try:
        decoded = bytes(pure_data).decode('utf-8', errors='ignore')
    except:
        decoded = bytes(pure_data).decode('latin-1')
    
    print(f"[OK] Decoded string: {len(decoded)} chars (before filter)")
    
    # 應用與 Android 相同的白名單過濾
    filtered = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', decoded)
    print(f"[OK] After whitelist: {len(filtered)} chars")
    
    return filtered

def compare_iphone_vs_android(iphone_txt, android_log):
    """比對 iPhone (官方標準) vs Android (我們的實作)"""
    
    print("=" * 70)
    print(" iPhone (Official) vs Android (Our App) - Comparison")
    print("=" * 70)
    
    # 1. 提取 iPhone 純數據
    print("\n[Step 1] Extracting iPhone clean data...")
    iphone_csv = extract_iphone_payload(iphone_txt)
    
    # 存檔供檢查
    with open('tree_project/Tree_app_equipment_info/iphone_clean_data.csv', 'w', encoding='utf-8') as f:
        f.write(iphone_csv)
    print("[OK] Saved to: iphone_clean_data.csv")
    
    # 2. 解析成紀錄
    iphone_records = {}
    for line in iphone_csv.splitlines():
        line = line.strip()
        if line.startswith('$') and ';' in line:
            parts = line.split(';')
            if len(parts) > 6:
                rec_id = parts[6].strip()
                if rec_id:
                    iphone_records[rec_id] = line
    
    print(f"[OK] iPhone reconstructed: {len(iphone_records)} records")
    
    # 3. 從 Android log 重建 (使用我們的邏輯)
    print("\n[Step 2] Reconstructing from Android log...")
    
    # 讀取 Android log
    content = ""
    for enc in ['utf-16', 'utf-8']:
        try:
            with open(android_log, 'r', encoding=enc) as f:
                content = f.read()
            break
        except:
            continue
    
    # 提取 [BLE RAW]
    raw_fragments = []
    for line in content.splitlines():
        if "[BLE RAW]" in line:
            parts = line.split("[BLE RAW]")
            if len(parts) > 1:
                hex_str = parts[1].strip()
                if hex_str:
                    raw_fragments.append(hex_str)
    
    # 重組
    full_bytes = []
    for hex_line in raw_fragments:
        try:
            clean_hex = hex_line.replace(' ', '')
            for i in range(0, len(clean_hex), 2):
                if i+2 <= len(clean_hex):
                    full_bytes.append(int(clean_hex[i:i+2], 16))
        except:
            pass
    
    # 應用目前的過濾器
    cleaned = []
    i = 0
    while i < len(full_bytes):
        if (i + 2 < len(full_bytes) and
            full_bytes[i] == 0x44 and
            full_bytes[i+1] == 0xCD and
            full_bytes[i+2] == 0x00):
            i += 3
            continue
        if (i + 2 < len(full_bytes) and
            full_bytes[i] == 0x44 and
            full_bytes[i+1] == 0x36 and
            full_bytes[i+2] == 0x00):
            i += 3
            continue
        if full_bytes[i] > 0x7E and full_bytes[i] != 0x0D and full_bytes[i] != 0x0A:
            i += 1
            if i < len(full_bytes):
                i += 1  # 配對移除
            continue
        cleaned.append(full_bytes[i])
        i += 1
    
    android_csv = bytes(cleaned).decode('utf-8', errors='ignore')
    android_csv = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', android_csv)
    
    android_records = {}
    for line in android_csv.splitlines():
        line = line.strip()
        if line.startswith('$') and ';' in line:
            parts = line.split(';')
            if len(parts) > 6:
                rec_id = parts[6].strip()
                if rec_id:
                    android_records[rec_id] = line
    
    print(f"[OK] Android reconstructed: {len(android_records)} records")
    
    # 4. 比對
    print("\n[Step 3] Comparing...")
    print("-" * 70)
    
    mismatches = 0
    for rec_id, iphone_line in list(iphone_records.items())[:20]:  # 只看前 20 筆
        if rec_id in android_records:
            if iphone_line != android_records[rec_id]:
                print(f"\n[DIFF] ID: {rec_id}")
                print(f"  iPhone: {iphone_line[:80]}...")
                print(f"  Android: {android_records[rec_id][:80]}...")
                mismatches += 1
        else:
            print(f"[MISSING] ID: {rec_id} not in Android")
            mismatches += 1
    
    if mismatches == 0:
        print("\n[SUCCESS] First 20 records match 100%!")
    else:
        print(f"\n[RESULT] {mismatches}/20 records have differences")
    
    print("=" * 70)

if __name__ == "__main__":
    iphone_file = 'tree_project/Tree_app_equipment_info/比對用/1st_version(101-150).txt'
    android_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    
    compare_iphone_vs_android(iphone_file, android_file)

