import json

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

# 分析 5-byte 封包後面的 20-byte 封包開頭
print("=== 5-byte 封包後面的封包開頭分析 ===")
print()

markers = {}
for i in range(len(notifications) - 1):
    if notifications[i]['len'] == 5:
        next_pkt = notifications[i + 1]
        if next_pkt['len'] >= 3:
            marker = next_pkt['bytes'][:3]
            marker_hex = marker.hex().upper()
            markers[marker_hex] = markers.get(marker_hex, 0) + 1

print("5-byte 封包後面的 3-byte 標記統計:")
for marker, count in sorted(markers.items(), key=lambda x: -x[1]):
    b0, b1, b2 = bytes.fromhex(marker)
    ascii_repr = ''.join([chr(b) if 0x20 <= b <= 0x7E else f'[{b:02X}]' for b in [b0, b1, b2]])
    print(f"  {marker}: {count:3d} 次  ({ascii_repr})")

print()
print("=" * 60)
print()

# 分析所有 44 xx 00 模式
print("=== 所有 44 xx 00 封包開頭 ===")
all_44_markers = {}
for n in notifications:
    if n['len'] >= 3 and n['bytes'][0] == 0x44 and n['bytes'][2] == 0x00:
        marker = n['bytes'][:3].hex().upper()
        all_44_markers[marker] = all_44_markers.get(marker, 0) + 1

for marker, count in sorted(all_44_markers.items(), key=lambda x: -x[1]):
    print(f"  {marker}: {count} 次")
