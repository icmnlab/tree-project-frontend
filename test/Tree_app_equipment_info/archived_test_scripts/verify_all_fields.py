"""
完整欄位驗證 - 檢查所有 33 個欄位是否正確解碼
"""

import json


def decode_packet(data):
    """封包解碼"""
    pkt_len = len(data)
    if pkt_len == 20:
        if len(data) >= 3 and data[0] == 0x44 and data[2] == 0x00:
            return data[3:]
        return data
    elif pkt_len == 5:
        return data[:3]
    else:
        return bytes([b for b in data if (0x20 <= b <= 0x7E) or b in (0x0D, 0x0A)])


def main():
    # 讀取 BLE log
    print("讀取 BLE log...")
    with open('ble_log.json', 'r', encoding='utf-8') as f:
        packets = json.load(f)

    # 提取 notifications
    notifications = []
    for pkt in packets:
        layers = pkt.get('_source', {}).get('layers', {})
        btatt = layers.get('btatt', {})
        if btatt.get('btatt.opcode') == '0x1b':
            value_str = btatt.get('btatt.value', '')
            if value_str:
                hex_bytes = value_str.replace(':', '')
                raw_bytes = bytes.fromhex(hex_bytes)
                notifications.append(raw_bytes)

    # 解碼
    decoded = bytearray()
    for pkt in notifications:
        decoded.extend(decode_packet(pkt))

    csv_text = decoded.decode('latin-1')

    # 解析我們的記錄
    our_records = {}
    for line in csv_text.split('\n'):
        line = line.strip()
        if line.startswith('$'):
            fields = line.split(';')
            if len(fields) > 6 and fields[6]:
                record_id = fields[6]
                our_records[record_id] = fields

    # 讀取官方 CSV
    official_records = {}
    with open('DATA_2.CSV', 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('$'):
                fields = line.split(';')
                if len(fields) > 6 and fields[6]:
                    record_id = fields[6]
                    official_records[record_id] = fields

    # 欄位名稱 (根據 CSV header)
    field_names = [
        'MARK', 'STATUS', 'TYPE', 'PROD', 'VER', 'SNR', 'ID', 'UNIT',
        'TRPH', 'REFH', 'P.OFF', 'DECL', 'LAT', 'N/S', 'LON', 'E/W',
        'ALTITUDE', 'HDOP', 'DATE', 'UTC', 'SEQ', 'AREA', 'VOL', 'SD',
        'HD', 'H', 'DIA', 'PITCH', 'AZ', 'X(m)', 'Y(m)', 'Z(m)', 'UTM ZONE'
    ]

    # 完整比對每個欄位
    print('\n=== 完整欄位比對 ===')
    total_fields = 0
    mismatched_fields = 0
    field_errors = {}

    for record_id, official_fields in official_records.items():
        if record_id in our_records:
            our_fields = our_records[record_id]
            for i in range(min(len(official_fields), len(our_fields))):
                total_fields += 1
                if official_fields[i] != our_fields[i]:
                    mismatched_fields += 1
                    if i not in field_errors:
                        field_errors[i] = []
                    field_errors[i].append({
                        'id': record_id,
                        'official': official_fields[i],
                        'ours': our_fields[i]
                    })

    print(f'總欄位數: {total_fields}')
    print(f'不匹配欄位數: {mismatched_fields}')
    accuracy = (total_fields - mismatched_fields) / total_fields * 100 if total_fields > 0 else 0
    print(f'欄位準確率: {accuracy:.4f}%')
    print()

    if field_errors:
        print('=== 欄位錯誤詳情 ===')
        for field_idx in sorted(field_errors.keys()):
            errors = field_errors[field_idx]
            field_name = field_names[field_idx] if field_idx < len(field_names) else f'Field{field_idx}'
            print(f'\n欄位 [{field_idx}] {field_name}: {len(errors)} 筆錯誤')
            for e in errors[:5]:  # 顯示前 5 筆
                print(f"  ID {e['id']}: 官方='{e['official']}' vs 我們='{e['ours']}'")
    else:
        print('✓ 所有欄位完全匹配！')

    # 檢查 DIA (胸徑) 欄位
    print('\n=== DIA (胸徑) 欄位分析 ===')
    dia_values = set()
    for record_id, fields in official_records.items():
        if len(fields) > 26:
            dia = fields[26].strip()
            dia_values.add(dia)
    
    print(f'DIA 欄位所有不同值: {dia_values}')
    if dia_values == {''} or dia_values == set():
        print('結論：VLGEO2 的 CSV 中 DIA 欄位全部為空，確實不會測量胸徑')


if __name__ == '__main__':
    main()
