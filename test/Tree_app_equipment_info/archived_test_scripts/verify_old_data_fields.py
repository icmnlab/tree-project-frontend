"""
OLD_DATA 完整欄位驗證
"""

import re


def decode_packet(data):
    pkt_len = len(data)
    if pkt_len == 20:
        if len(data) >= 3 and data[0] == 0x44 and data[2] == 0x00:
            return data[3:]
        return data
    elif pkt_len == 5:
        return data[:3]
    else:
        return bytes([b for b in data if (0x20 <= b <= 0x7E) or b in (0x0D, 0x0A)])


field_names = [
    'MARK', 'STATUS', 'TYPE', 'PROD', 'VER', 'SNR', 'ID', 'UNIT',
    'TRPH', 'REFH', 'P.OFF', 'DECL', 'LAT', 'N/S', 'LON', 'E/W',
    'ALTITUDE', 'HDOP', 'DATE', 'UTC', 'SEQ', 'AREA', 'VOL', 'SD',
    'HD', 'H', 'DIA', 'PITCH', 'AZ', 'X(m)', 'Y(m)', 'Z(m)', 'UTM ZONE'
]

# 讀取 nRF Connect log
notifications = []
with open('old_data_ble.txt', 'r', encoding='utf-8') as f:
    for line in f:
        if 'Notification received from' in line and 'value: (0x)' in line:
            match = re.search(r'value: \(0x\) ([0-9A-Fa-f\-]+)', line)
            if match:
                hex_str = match.group(1).replace('-', '')
                raw_bytes = bytes.fromhex(hex_str)
                notifications.append(raw_bytes)

print(f"總封包數: {len(notifications)}")

# 解碼
decoded = bytearray()
for pkt in notifications:
    decoded.extend(decode_packet(pkt))
csv_text = decoded.decode('latin-1')

# 解析記錄
our_records = {}
for line in csv_text.split('\n'):
    line = line.strip()
    if line.startswith('$'):
        fields = line.split(';')
        if len(fields) > 6 and fields[6]:
            our_records[fields[6]] = fields

# 讀取官方 CSV
official_records = {}
with open('old_data.CSV', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line.startswith('$'):
            fields = line.split(';')
            if len(fields) > 6 and fields[6]:
                official_records[fields[6]] = fields

# 比對
total = mismatched = 0
errors = {}
for rid, off in official_records.items():
    if rid in our_records:
        ours = our_records[rid]
        for i in range(min(len(off), len(ours))):
            total += 1
            if off[i] != ours[i]:
                mismatched += 1
                if i not in errors:
                    errors[i] = []
                errors[i].append({'id': rid, 'off': off[i], 'ours': ours[i]})

print('\n=== OLD_DATA 完整欄位比對 ===')
print(f'總欄位數: {total}')
print(f'不匹配: {mismatched}')
print(f'準確率: {(total-mismatched)/total*100:.2f}%' if total > 0 else '無資料')

if errors:
    for idx in sorted(errors.keys()):
        name = field_names[idx] if idx < len(field_names) else f'F{idx}'
        print(f'\n欄位[{idx}] {name}: {len(errors[idx])}筆')
        for e in errors[idx][:3]:
            print(f"  ID {e['id']}: '{e['off']}' vs '{e['ours']}'")
else:
    print('\n✓ 所有欄位完全匹配！')
