import json

with open('ble_log.json', 'r', encoding='utf-8') as f:
    packets = json.load(f)

# 找出 Notification 封包
notifications = []
for i, pkt in enumerate(packets):
    layers = pkt.get('_source', {}).get('layers', {})
    btatt = layers.get('btatt', {})
    if btatt.get('btatt.opcode') == '0x1b':
        value_str = btatt.get('btatt.value', '')
        if value_str:
            hex_bytes = value_str.replace(':', '')
            raw_bytes = bytes.fromhex(hex_bytes)
            notifications.append({
                'idx': i,
                'hex': hex_bytes,
                'bytes': raw_bytes,
                'len': len(raw_bytes)
            })

# 重建數據流
byte_to_packet = []
full_data = bytearray()
for idx, n in enumerate(notifications):
    for b in n['bytes']:
        byte_to_packet.append(idx)
        full_data.append(b)

# 搜尋 10340
full_str = full_data.decode('latin-1')
pos = full_str.find(';10340;')
if pos >= 0:
    start = full_str.rfind('$', 0, pos)
    end = full_str.find('\n', pos)
    if end == -1:
        end = pos + 200
    
    print('ID 10340 附近的封包:')
    involved = set()
    for i in range(start, min(end, len(full_str))):
        involved.add(byte_to_packet[i])
    
    for pkt_idx in sorted(involved):
        n = notifications[pkt_idx]
        hex_str = ' '.join([f'{b:02X}' for b in n['bytes']])
        ascii_str = ''.join([chr(b) if 0x20 <= b <= 0x7E else '.' for b in n['bytes']])
        pkt_len = n['len']
        print(f'封包 #{pkt_idx} (len={pkt_len}):')
        print(f'  Hex: {hex_str}')
        print(f'  ASCII: {ascii_str}')
        if n['bytes'][:3] == b'\x44\xCD\x00':
            print('  ⚠️ 以 44 CD 00 開頭!')
        print()
