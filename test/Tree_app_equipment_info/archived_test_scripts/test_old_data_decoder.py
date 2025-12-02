"""
VLGEO2 BLE 協議解碼器 - nRF Connect Log 格式
測試 old_data_ble.txt
"""

import re
import csv


def parse_nrf_connect_log(log_path):
    """解析 nRF Connect log 檔案，提取 Notification 封包"""
    notifications = []
    
    with open(log_path, 'r', encoding='utf-8') as f:
        for line in f:
            # 尋找 Notification received 行
            # 格式：I	20:56:21.356	Notification received from ..., value: (0x) XX-XX-XX...
            if 'Notification received from' in line and 'value: (0x)' in line:
                # 提取 hex 數據
                match = re.search(r'value: \(0x\) ([0-9A-Fa-f\-]+)', line)
                if match:
                    hex_str = match.group(1).replace('-', '')
                    raw_bytes = bytes.fromhex(hex_str)
                    notifications.append({
                        'hex': hex_str,
                        'bytes': raw_bytes,
                        'len': len(raw_bytes)
                    })
    
    return notifications


def decode_vlgeo2_ble_packets(notifications):
    """正確解碼 VLGEO2 BLE 封包"""
    decoded_data = bytearray()
    stats = {
        'normal_20': 0,
        'residual_5': 0,
        'marker_44xx00': 0,
        'other': 0,
        'bytes_dropped': 0
    }
    
    for n in notifications:
        pkt_bytes = n['bytes']
        pkt_len = n['len']
        
        if pkt_len == 20:
            # 檢查是否以 44 xx 00 開頭
            if len(pkt_bytes) >= 3 and pkt_bytes[0] == 0x44 and pkt_bytes[2] == 0x00:
                decoded_data.extend(pkt_bytes[3:])
                stats['marker_44xx00'] += 1
                stats['bytes_dropped'] += 3
            else:
                decoded_data.extend(pkt_bytes)
                stats['normal_20'] += 1
        
        elif pkt_len == 5:
            decoded_data.extend(pkt_bytes[:3])
            stats['residual_5'] += 1
            stats['bytes_dropped'] += 2
        
        else:
            for b in pkt_bytes:
                if 0x20 <= b <= 0x7E or b in (0x0D, 0x0A):
                    decoded_data.append(b)
            stats['other'] += 1
    
    return decoded_data.decode('latin-1'), stats


def compare_with_official(decoded_csv, official_csv_path):
    """與官方 CSV 比對"""
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
    print("=== OLD_DATA 測試 ===\n")
    
    # 讀取 nRF Connect log
    print("讀取 nRF Connect log...")
    notifications = parse_nrf_connect_log('old_data_ble.txt')
    print(f"總 Notification 封包數: {len(notifications)}")
    print()
    
    # 統計封包長度分布
    len_dist = {}
    for n in notifications:
        l = n['len']
        len_dist[l] = len_dist.get(l, 0) + 1
    print("封包長度分布:")
    for l in sorted(len_dist.keys()):
        print(f"  {l} bytes: {len_dist[l]}")
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
    
    # 與官方比對
    print("=== 與官方 CSV (old_data.CSV) 比對 ===")
    matches, mismatches, total = compare_with_official(decoded_csv, 'old_data.CSV')
    
    accuracy = matches / total * 100 if total > 0 else 0
    print(f"匹配: {matches}/{total} ({accuracy:.2f}%)")
    print()
    
    if mismatches:
        print(f"不匹配的記錄 ({len(mismatches)} 筆):")
        for record_id, diffs in mismatches[:10]:
            if diffs == 'MISSING':
                print(f"  ID {record_id}: 缺失")
            else:
                print(f"  ID {record_id}:")
                for field_idx, official, ours in diffs:
                    print(f"    [{field_idx}]: 官方='{official}' vs 我們='{ours}'")


if __name__ == '__main__':
    main()
