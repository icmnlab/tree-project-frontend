#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析官方 Haglof Link App 的過濾策略
比對 Android Serial Log 與官方 App 輸出，找出 100% 復原的秘訣
"""

import re

def parse_serial_log(filepath):
    """解析 Android Serial Log (Hex格式)"""
    data_stream = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            # 移除時間戳記 (格式: HH:MM:SS.mmm)
            if re.match(r'^\d{2}:\d{2}:\d{2}\.\d{3}', line):
                line = re.sub(r'^\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+', '', line)
            
            # 將 Hex 字串轉換為 bytes
            hex_parts = line.split()
            for hex_str in hex_parts:
                try:
                    byte_val = int(hex_str, 16)
                    data_stream.append(byte_val)
                except:
                    pass
    
    return data_stream

def analyze_packet_logger_patterns(data_stream):
    """分析 PacketLogger 雜訊模式"""
    print("=" * 80)
    print(" PacketLogger 雜訊模式分析")
    print("=" * 80)
    print()
    
    # 統計封包頭出現次數
    pattern_0x44_0xCD_0x00 = 0
    pattern_0x44_0x36_0x00 = 0
    
    # 統計配對雜訊 (Non-ASCII + ASCII 組合)
    non_ascii_ascii_pairs = []
    
    # 統計獨立 Non-ASCII bytes
    isolated_non_ascii = []
    
    i = 0
    while i < len(data_stream) - 2:
        # 檢測封包頭
        if data_stream[i] == 0x44:
            if data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00:
                pattern_0x44_0xCD_0x00 += 1
                
                # 檢查前面 2 bytes 是否為配對雜訊
                if i >= 2:
                    byte_minus_2 = data_stream[i-2]
                    byte_minus_1 = data_stream[i-1]
                    
                    if byte_minus_2 > 0x7E or byte_minus_1 > 0x7E:
                        non_ascii_ascii_pairs.append((byte_minus_2, byte_minus_1, i))
                
                i += 3
                continue
            
            elif data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00:
                pattern_0x44_0x36_0x00 += 1
                i += 3
                continue
        
        # 檢測獨立 Non-ASCII bytes (排除換行符)
        if data_stream[i] > 0x7E and data_stream[i] not in [0x0D, 0x0A]:
            # 檢查是否在封包頭前的配對中
            is_in_pair = False
            if i + 2 < len(data_stream):
                if data_stream[i+2] == 0x44:
                    is_in_pair = True
            
            if not is_in_pair:
                isolated_non_ascii.append((data_stream[i], i))
        
        i += 1
    
    print(f"[封包頭統計]")
    print(f"  0x44 0xCD 0x00: {pattern_0x44_0xCD_0x00} 次")
    print(f"  0x44 0x36 0x00: {pattern_0x44_0x36_0x00} 次")
    print()
    
    print(f"[配對雜訊統計] (封包頭前的 Non-ASCII + ASCII)")
    print(f"  總計: {len(non_ascii_ascii_pairs)} 次")
    if non_ascii_ascii_pairs[:10]:
        print(f"  範例 (前 10 個):")
        for byte1, byte2, pos in non_ascii_ascii_pairs[:10]:
            print(f"    Pos {pos-2}: 0x{byte1:02X} 0x{byte2:02X} → 封包頭")
    print()
    
    print(f"[獨立 Non-ASCII bytes]")
    print(f"  總計: {len(isolated_non_ascii)} 個")
    if isolated_non_ascii[:20]:
        print(f"  範例 (前 20 個):")
        for byte_val, pos in isolated_non_ascii[:20]:
            print(f"    Pos {pos}: 0x{byte_val:02X}")
    print()
    
    return {
        'packet_headers': pattern_0x44_0xCD_0x00 + pattern_0x44_0x36_0x00,
        'noise_pairs': len(non_ascii_ascii_pairs),
        'isolated_non_ascii': len(isolated_non_ascii)
    }

def apply_v13_1_filter(data_stream):
    """套用 v13.1 的過濾邏輯"""
    cleaned_data = []
    i = 0
    
    while i < len(data_stream):
        # 偵測 PacketLogger 封包頭
        is_packet_logger_header = False
        header_length = 0
        
        if i + 2 < len(data_stream):
            if data_stream[i] == 0x44 and data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00:
                is_packet_logger_header = True
                header_length = 3
            elif data_stream[i] == 0x44 and data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00:
                is_packet_logger_header = True
                header_length = 3
        
        if is_packet_logger_header:
            # 回溯清理：移除前面的雜訊對
            if len(cleaned_data) >= 2:
                if cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E:
                    cleaned_data.pop()
                    cleaned_data.pop()
            elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                cleaned_data.pop()
            
            i += header_length
            continue
        
        # 獨立的 Non-ASCII byte (保留換行符)
        if data_stream[i] > 0x7E and data_stream[i] not in [0x0D, 0x0A]:
            i += 1
            continue
        
        # 保留正常 byte
        cleaned_data.append(data_stream[i])
        i += 1
    
    return cleaned_data

def reconstruct_csv_from_cleaned_data(cleaned_data):
    """從清洗後的數據重建 CSV"""
    try:
        csv_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        csv_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # 只保留 VLGEO 合法字元
    csv_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', csv_text)
    
    # 統計數據行
    data_lines = []
    for line in csv_text.split('\n'):
        line = line.strip()
        if line.startswith('$'):
            data_lines.append(line)
    
    return data_lines

def compare_with_ground_truth(reconstructed_lines, ground_truth_file):
    """與官方 App 輸出比對"""
    # 讀取官方 App 輸出
    gt_lines = []
    with open(ground_truth_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('$'):
                gt_lines.append(line)
    
    print("=" * 80)
    print(" 與官方 App 輸出比對")
    print("=" * 80)
    print()
    
    print(f"[筆數比對]")
    print(f"  我們重建: {len(reconstructed_lines)} 筆")
    print(f"  官方 App: {len(gt_lines)} 筆")
    print()
    
    # 逐筆比對
    matches = 0
    differences = []
    
    max_len = min(len(reconstructed_lines), len(gt_lines))
    for i in range(max_len):
        if reconstructed_lines[i] == gt_lines[i]:
            matches += 1
        else:
            differences.append({
                'line': i + 1,
                'ours': reconstructed_lines[i][:100],
                'official': gt_lines[i][:100]
            })
    
    accuracy = matches / max_len * 100 if max_len > 0 else 0
    
    print(f"[準確率]")
    print(f"  完全匹配: {matches}/{max_len} 筆 ({accuracy:.1f}%)")
    print()
    
    if differences and len(differences) <= 20:
        print(f"[差異列表] (共 {len(differences)} 筆)")
        print("-" * 80)
        for diff in differences[:10]:
            print(f"\n  Line {diff['line']}:")
            print(f"    我們:   {diff['ours']}")
            print(f"    官方:   {diff['official']}")
    
    return accuracy

def main():
    print("\n")
    print("=" * 80)
    print(" 官方 Haglof Link App 過濾策略逆向工程")
    print("=" * 80)
    print()
    
    # 1. 解析 Android Serial Log
    serial_log = 'tree_project/Tree_app_equipment_info/serial_20251125_200547(DATA_2).txt'
    ground_truth = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    print("[Step 1] 解析 Android Serial Log...")
    data_stream = parse_serial_log(serial_log)
    print(f"  原始 byte stream: {len(data_stream)} bytes")
    print()
    
    # 2. 分析雜訊模式
    print("[Step 2] 分析 PacketLogger 雜訊模式...")
    noise_stats = analyze_packet_logger_patterns(data_stream)
    
    # 3. 套用 v13.1 過濾器
    print("[Step 3] 套用 v13.1 過濾器...")
    cleaned_data = apply_v13_1_filter(data_stream)
    print(f"  清洗後: {len(cleaned_data)} bytes")
    print(f"  移除雜訊: {len(data_stream) - len(cleaned_data)} bytes")
    print()
    
    # 4. 重建 CSV
    print("[Step 4] 重建 CSV...")
    reconstructed_lines = reconstruct_csv_from_cleaned_data(cleaned_data)
    print(f"  重建數據: {len(reconstructed_lines)} 筆")
    print()
    
    # 5. 與官方 App 比對
    print("[Step 5] 與官方 App 輸出比對...")
    accuracy = compare_with_ground_truth(reconstructed_lines, ground_truth)
    print()
    
    print("=" * 80)
    print()
    
    if accuracy >= 99:
        print("🎉 恭喜！我們已經達到官方 App 的水準！")
    elif accuracy >= 90:
        print("✅ 很接近了！還有一些小差異需要處理。")
    else:
        print("⚠️  還有較大差距，需要進一步分析雜訊模式。")
    
    print()
    print("=" * 80)

if __name__ == "__main__":
    main()






