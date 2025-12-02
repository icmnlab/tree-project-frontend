"""
VLGEO2 BLE 協議深度理解
找出封包邊界和數據對齊問題
"""
import json

# 讀取 BLE log
with open('ble_log.json', 'r', encoding='utf-8') as f:
    packets = json.load(f)

# 找出所有 Notification 封包
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
                'pkt_num': i,
                'hex': hex_bytes,
                'bytes': raw_bytes,
                'len': len(raw_bytes)
            })

print(f"總 Notification 封包數: {len(notifications)}")
print()

# 統計封包長度
lengths = {}
for n in notifications:
    l = n['len']
    lengths[l] = lengths.get(l, 0) + 1

print("封包長度分布:")
for l, count in sorted(lengths.items()):
    print(f"  {l} bytes: {count} 個")

print()

# 找出問題 ID 附近的封包
print("=" * 60)
print("搜尋問題 ID 附近的封包邊界")
print("=" * 60)
print()

# 重建數據流，記錄每個 byte 來自哪個封包
byte_to_packet = []
full_data = bytearray()

for idx, n in enumerate(notifications):
    for b in n['bytes']:
        byte_to_packet.append(idx)
        full_data.append(b)

# 搜尋問題 ID
problem_ids = ['10071', '10087', '10092']
full_str = full_data.decode('latin-1')

for pid in problem_ids:
    pattern = f';{pid};'
    pos = full_str.find(pattern)
    if pos >= 0:
        # 找出這筆記錄的範圍
        start = full_str.rfind('$', 0, pos)
        end = full_str.find('\n', pos)
        if end == -1:
            end = min(pos + 200, len(full_str))
        
        print(f"=== ID {pid} ===")
        print(f"記錄位置: {start} - {end}")
        print()
        
        # 找出涉及的封包
        involved_packets = set()
        for i in range(start, end):
            involved_packets.add(byte_to_packet[i])
        
        print(f"涉及的封包: {sorted(involved_packets)}")
        print()
        
        # 顯示每個封包的內容
        for pkt_idx in sorted(involved_packets):
            n = notifications[pkt_idx]
            # 計算這個封包在總數據流中的位置
            pkt_start = sum(notifications[i]['len'] for i in range(pkt_idx))
            pkt_end = pkt_start + n['len']
            
            # 是否在記錄範圍內
            in_record = pkt_start < end and pkt_end > start
            
            if in_record:
                # 擷取封包中屬於這筆記錄的部分
                local_start = max(0, start - pkt_start)
                local_end = min(n['len'], end - pkt_start)
                
                relevant_bytes = n['bytes'][local_start:local_end]
                hex_str = ' '.join([f'{b:02X}' for b in n['bytes']])
                ascii_str = ''.join([chr(b) if 0x20 <= b <= 0x7E else '.' for b in n['bytes']])
                
                print(f"封包 #{pkt_idx} (len={n['len']}, 位置 {pkt_start}-{pkt_end}):")
                print(f"  Hex: {hex_str}")
                print(f"  ASCII: {ascii_str}")
                
                # 檢查是否以 44 CD 00 開頭
                if n['bytes'][:3] == b'\x44\xCD\x00':
                    print(f"  ⚠️ 以 44 CD 00 開頭!")
                print()
        
        print("-" * 60)
        print()
