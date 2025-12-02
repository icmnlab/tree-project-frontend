"""
VLGEO2 BLE 協議正確解碼器 v2

基於深度分析的發現：
1. 正常封包: 20 bytes
2. 殘留封包: 5 bytes (前 3 bytes 是數據，後 2 bytes 是雜訊)
3. 標記封包: 以 44 CD 00 開頭 (跳過前 3 bytes)

正確的解碼流程：
1. 識別封包類型
2. 根據類型擷取有效數據
3. 合併為完整的 CSV
"""

import json
import csv


def decode_vlgeo2_ble_packets(notifications):
    """
    正確解碼 VLGEO2 BLE 封包
    
    Args:
        notifications: List of {'hex': hex_string, 'bytes': bytes, 'len': int}
    
    Returns:
        Decoded CSV string
    """
    decoded_data = bytearray()
    stats = {
        'normal_20': 0,
        'residual_5': 0,
        'marker_44xx00': 0,
        'other': 0,
        'bytes_dropped': 0
    }
    
    for idx, n in enumerate(notifications):
        pkt_bytes = n['bytes']
        pkt_len = n['len']
        
        # 檢查封包類型
        if pkt_len == 20:
            # 20-byte 封包
            # 檢查是否以 44 xx 00 開頭 (PacketLogger 標記)
            if len(pkt_bytes) >= 3 and pkt_bytes[0] == 0x44 and pkt_bytes[2] == 0x00:
                # 以 44 xx 00 開頭的標記封包：跳過前 3 bytes
                decoded_data.extend(pkt_bytes[3:])
                stats['marker_44xx00'] += 1
                stats['bytes_dropped'] += 3
            else:
                # 正常的 20-byte 數據封包
                decoded_data.extend(pkt_bytes)
                stats['normal_20'] += 1
        
        elif pkt_len == 5:
            # 5-byte 殘留封包：只保留前 3 bytes
            decoded_data.extend(pkt_bytes[:3])
            stats['residual_5'] += 1
            stats['bytes_dropped'] += 2
        
        else:
            # 其他長度的封包：過濾並保留 ASCII
            for b in pkt_bytes:
                if 0x20 <= b <= 0x7E or b in (0x0D, 0x0A):  # 可打印 ASCII + 換行
                    decoded_data.append(b)
            stats['other'] += 1
    
    return decoded_data.decode('latin-1'), stats


def compare_with_official(decoded_csv, official_csv_path):
    """
    與官方 CSV 比對
    """
    # 解析解碼後的 CSV
    our_records = {}
    for line in decoded_csv.split('\n'):
        line = line.strip()
        if line.startswith('$'):
            fields = line.split(';')
            if len(fields) > 6 and fields[6]:
                record_id = fields[6]
                our_records[record_id] = fields
    
    # 讀取官方 CSV
    official_records = {}
    with open(official_csv_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('$'):
                fields = line.split(';')
                if len(fields) > 6 and fields[6]:
                    record_id = fields[6]
                    official_records[record_id] = fields
    
    # 比對
    matches = 0
    mismatches = []
    
    for record_id, official_fields in official_records.items():
        if record_id in our_records:
            our_fields = our_records[record_id]
            
            # 比對每個欄位
            is_match = True
            field_diffs = []
            for i in range(min(len(official_fields), len(our_fields))):
                if official_fields[i] != our_fields[i]:
                    is_match = False
                    field_diffs.append((i, official_fields[i], our_fields[i]))
            
            if is_match:
                matches += 1
            else:
                mismatches.append((record_id, field_diffs))
        else:
            mismatches.append((record_id, 'MISSING'))
    
    return matches, mismatches, len(official_records)


def main():
    # 讀取 BLE log
    print("讀取 BLE log...")
    with open('ble_log.json', 'r', encoding='utf-8') as f:
        packets = json.load(f)
    
    # 找出 Notification 封包
    notifications = []
    for pkt in packets:
        layers = pkt.get('_source', {}).get('layers', {})
        btatt = layers.get('btatt', {})
        if btatt.get('btatt.opcode') == '0x1b':
            value_str = btatt.get('btatt.value', '')
            if value_str:
                hex_bytes = value_str.replace(':', '')
                raw_bytes = bytes.fromhex(hex_bytes)
                notifications.append({
                    'hex': hex_bytes,
                    'bytes': raw_bytes,
                    'len': len(raw_bytes)
                })
    
    print(f"總 Notification 封包數: {len(notifications)}")
    print()
    
    # 解碼
    print("解碼中...")
    decoded_csv, stats = decode_vlgeo2_ble_packets(notifications)
    
    print("=== 解碼統計 ===")
    print(f"  正常 20-byte 封包: {stats['normal_20']}")
    print(f"  5-byte 殘留封包: {stats['residual_5']}")
    print(f"  44 xx 00 標記封包: {stats['marker_44xx00']}")
    print(f"  其他封包: {stats['other']}")
    print(f"  丟棄的 bytes: {stats['bytes_dropped']}")
    print()
    
    # 驗證問題 ID
    print("=== 驗證問題 ID ===")
    problem_ids = ['10071', '10087', '10092']
    
    for pid in problem_ids:
        pattern = f';{pid};'
        pos = decoded_csv.find(pattern)
        if pos >= 0:
            start = decoded_csv.rfind('$', 0, pos)
            end = decoded_csv.find('\n', pos)
            if end == -1:
                end = pos + 200
            
            record = decoded_csv[start:end]
            fields = record.split(';')
            
            print(f"ID {pid}:")
            if len(fields) > 24:
                print(f"  UTC [19]: '{fields[19]}'")
                print(f"  LON [14]: '{fields[14]}'")
                print(f"  HD  [24]: '{fields[24]}'")
            print()
    
    # 與官方比對
    print("=== 與官方 CSV 比對 ===")
    matches, mismatches, total = compare_with_official(decoded_csv, 'DATA_2.CSV')
    
    accuracy = matches / total * 100 if total > 0 else 0
    print(f"匹配: {matches}/{total} ({accuracy:.2f}%)")
    print()
    
    if mismatches:
        print(f"不匹配的記錄 ({len(mismatches)} 筆):")
        for record_id, diffs in mismatches[:10]:  # 只顯示前 10 筆
            if diffs == 'MISSING':
                print(f"  ID {record_id}: 缺失")
            else:
                print(f"  ID {record_id}:")
                for field_idx, official, ours in diffs:
                    print(f"    [{field_idx}]: 官方='{official}' vs 我們='{ours}'")


if __name__ == '__main__':
    main()
