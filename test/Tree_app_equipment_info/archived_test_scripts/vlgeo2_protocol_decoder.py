"""
VLGEO2 BLE 協議正確解碼器

基於深度分析的發現：
1. BLE 封包使用 Nordic UART Service (NUS)
2. 每個封包最多 20 bytes (BLE ATT MTU)
3. 封包開頭有時會有 "44 CD 00" 標記 (PacketLogger 分段標記)
4. 這個標記及其前面的殘留 bytes 需要被移除

正確的解碼策略：
- 識別並移除 "44 CD 00" 封包標記
- 同時移除標記前面的殘留 bytes (非 ASCII 可打印字符)
"""

import json
import re


def decode_vlgeo2_ble_stream(notifications):
    """
    正確解碼 VLGEO2 BLE 數據流
    
    Args:
        notifications: List of (packet_num, hex_string) tuples
    
    Returns:
        Decoded CSV string
    """
    # Step 1: 合併所有封包為完整的 byte 流
    full_data = bytearray()
    for pkt_num, value_str in notifications:
        hex_bytes = value_str.replace(':', '')
        try:
            raw_bytes = bytes.fromhex(hex_bytes)
            full_data.extend(raw_bytes)
        except:
            continue
    
    # Step 2: 識別並移除封包標記 "44 CD 00" 及其前面的殘留 bytes
    # 模式：[非 ASCII 可打印字符]* + 44 CD 00
    cleaned_data = bytearray()
    i = 0
    removed_sequences = []
    
    while i < len(full_data):
        # 檢查是否是 44 CD 00 標記
        if i + 2 < len(full_data) and full_data[i] == 0x44 and full_data[i+1] == 0xCD and full_data[i+2] == 0x00:
            # 找到封包標記，跳過它
            removed_sequences.append((i, '44 CD 00'))
            i += 3
            continue
        
        # 檢查是否是 [residual] + 44 CD 00 的模式
        # 向前看，如果接下來 1-3 bytes 後是 44 CD 00，則這些是殘留 bytes
        found_residual = False
        for lookahead in range(1, 4):  # 檢查 1-3 bytes 的殘留
            if i + lookahead + 2 < len(full_data):
                if (full_data[i + lookahead] == 0x44 and 
                    full_data[i + lookahead + 1] == 0xCD and 
                    full_data[i + lookahead + 2] == 0x00):
                    # 檢查這些殘留 bytes 是否為非正常 CSV 字符
                    residual = full_data[i:i + lookahead]
                    # 殘留判斷：包含非 ASCII 可打印字符，或是在數字欄位中出現字母
                    has_non_printable = any(b < 0x20 or b > 0x7E for b in residual)
                    
                    if has_non_printable:
                        # 移除殘留 + 封包標記
                        removed_sequences.append((i, f'{residual.hex()} + 44 CD 00'))
                        i += lookahead + 3
                        found_residual = True
                        break
        
        if found_residual:
            continue
        
        # 正常字符，保留
        cleaned_data.append(full_data[i])
        i += 1
    
    return cleaned_data.decode('latin-1'), removed_sequences


def parse_csv_records(csv_data):
    """
    解析 CSV 記錄
    """
    records = []
    
    # 以 $ 分割記錄
    lines = csv_data.split('\n')
    current_record = ''
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        if line.startswith('$'):
            if current_record:
                records.append(current_record)
            current_record = line
        else:
            current_record += line
    
    if current_record:
        records.append(current_record)
    
    return records


def main():
    # 讀取 BLE log
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
                notifications.append((0, value_str))
    
    print(f"總 Notification 封包數: {len(notifications)}")
    
    # 解碼
    decoded_csv, removed = decode_vlgeo2_ble_stream(notifications)
    
    print(f"移除的封包標記數: {len(removed)}")
    print()
    
    # 顯示移除的序列
    print("=== 移除的雜訊序列 (前 20 個) ===")
    for pos, seq in removed[:20]:
        print(f"  位置 {pos}: {seq}")
    
    print()
    
    # 驗證問題 ID
    print("=== 驗證問題 ID ===")
    problem_ids = ['10071', '10087', '10092']
    
    for pid in problem_ids:
        pattern = f';{pid};'
        pos = decoded_csv.find(pattern)
        if pos >= 0:
            # 找出記錄
            start = decoded_csv.rfind('$', 0, pos)
            end = decoded_csv.find('$', pos + 1)
            if end == -1:
                end = min(pos + 200, len(decoded_csv))
            
            record = decoded_csv[start:end]
            fields = record.split(';')
            
            print(f"ID {pid}:")
            if len(fields) > 24:
                print(f"  UTC [19]: {fields[19]}")
                print(f"  LON [14]: {fields[14]}")
                print(f"  HD  [24]: {fields[24]}")
            print()


if __name__ == '__main__':
    main()
