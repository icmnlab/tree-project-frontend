"""
VLGEO2 BLE 協議深度分析
目標：理解儀器傳輸的封包格式，而非黑箱過濾
"""
import json

# 讀取 BLE log
with open('ble_log.json', 'r', encoding='utf-8') as f:
    packets = json.load(f)

print(f"總封包數: {len(packets)}")
print()

# 找出 Notification 封包 (Opcode 0x1b)
notifications = []
for i, pkt in enumerate(packets):
    layers = pkt.get('_source', {}).get('layers', {})
    btatt = layers.get('btatt', {})
    if btatt.get('btatt.opcode') == '0x1b':
        value_str = btatt.get('btatt.value', '')
        if value_str:
            notifications.append((i, value_str))

print(f"Notification 封包數: {len(notifications)}")
print()

# 重建完整數據流（含原始 bytes）
full_data = bytearray()
packet_boundaries = []  # 記錄每個封包的起始位置

for idx, (pkt_num, value_str) in enumerate(notifications):
    hex_bytes = value_str.replace(':', '')
    try:
        raw_bytes = bytes.fromhex(hex_bytes)
        packet_boundaries.append((len(full_data), pkt_num, len(raw_bytes)))
        full_data.extend(raw_bytes)
    except:
        pass

print("=== 問題 ID 的 Hex 層級分析 ===")
print()

problem_ids = ['10071', '10087', '10092']
full_str = full_data.decode('latin-1')

for pid in problem_ids:
    search_pattern = f';{pid};'
    pos = full_str.find(search_pattern)
    if pos >= 0:
        # 找出這筆記錄的完整範圍 (從 $ 到下一個 $)
        record_start = full_str.rfind('$', 0, pos)
        record_end = full_str.find('$', pos + 1)
        if record_end == -1:
            record_end = min(pos + 300, len(full_str))
        
        # 擷取記錄
        record = full_str[record_start:record_end]
        record_bytes = full_data[record_start:record_end]
        
        print(f"=== ID {pid} ===")
        print(f"位置: {record_start} - {record_end}")
        print()
        
        # 顯示原始 Hex
        print("原始 Hex (每 20 bytes 一行):")
        for i in range(0, len(record_bytes), 20):
            chunk = record_bytes[i:i+20]
            hex_str = ' '.join([f'{b:02X}' for b in chunk])
            ascii_str = ''.join([chr(b) if 0x20 <= b <= 0x7E else '.' for b in chunk])
            print(f"  {hex_str:<60} | {ascii_str}")
        print()
        
        # 分析雜訊位置
        print("雜訊分析:")
        # 找出 44 CD 00 的位置
        noise_marker = bytes([0x44, 0xCD, 0x00])
        noise_pos = record_bytes.find(noise_marker)
        if noise_pos >= 0:
            # 顯示雜訊前後的 bytes
            context_start = max(0, noise_pos - 5)
            context_end = min(len(record_bytes), noise_pos + 8)
            context = record_bytes[context_start:context_end]
            
            hex_context = ' '.join([f'{b:02X}' for b in context])
            ascii_context = ''.join([chr(b) if 0x20 <= b <= 0x7E else f'[{b:02X}]' for b in context])
            
            print(f"  雜訊位置: byte {noise_pos} (相對於記錄開頭)")
            print(f"  前後 Hex: {hex_context}")
            print(f"  前後 ASCII: {ascii_context}")
            
            # 判斷雜訊前面的 byte 是什麼
            if noise_pos > 0:
                prev_byte = record_bytes[noise_pos - 1]
                print(f"  雜訊前一個 byte: 0x{prev_byte:02X} ({chr(prev_byte) if 0x20 <= prev_byte <= 0x7E else 'non-printable'})")
        
        print()
        print("-" * 80)
        print()


