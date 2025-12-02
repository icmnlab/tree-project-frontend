#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
正確解析 Android Serial Log
處理混合格式的 Hex bytes (有空格和無空格混合)
"""

import re

def parse_serial_log_correctly(filepath):
    """正確解析 Serial Log"""
    all_bytes = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            
            # 移除時間戳記 (20:05:53.855) 和長度數字
            line = re.sub(r'^\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s*', '', line)
            
            # 現在 line 是純 Hex 字串，可能混合有空格和無空格的格式
            # 例如: "3B 3B 53 45 543B 3B 4D"
            
            # 分割成 tokens (以空格分隔)
            tokens = line.split()
            
            for token in tokens:
                # 每個 token 可能是：
                # - 單個 byte: "3B" (2個字元)
                # - 多個 bytes 連接: "543B" (4個字元), "7B44CD" (6個字元)
                
                # 將 token 每 2 個字元分割成一個 byte
                for i in range(0, len(token), 2):
                    if i + 2 <= len(token):
                        hex_str = token[i:i+2]
                        try:
                            byte_val = int(hex_str, 16)
                            all_bytes.append(byte_val)
                        except ValueError:
                            pass  # 略過無法解析的部分
    
    return all_bytes

def apply_v13_1_filter(data_stream):
    """套用 v13.1 過濾器"""
    cleaned_data = []
    i = 0
    
    removed_packet_headers = 0
    removed_noise_pairs = 0
    removed_isolated = 0
    
    while i < len(data_stream):
        # 偵測 PacketLogger 封包頭
        is_packet_logger_header = False
        header_length = 0
        
        if i + 2 < len(data_stream):
            if data_stream[i] == 0x44 and data_stream[i+1] == 0xCD and data_stream[i+2] == 0x00:
                is_packet_logger_header = True
                header_length = 3
                removed_packet_headers += 1
            elif data_stream[i] == 0x44 and data_stream[i+1] == 0x36 and data_stream[i+2] == 0x00:
                is_packet_logger_header = True
                header_length = 3
                removed_packet_headers += 1
        
        if is_packet_logger_header:
            # 回溯清理：移除前面的雜訊對
            backtrack_count = 0
            if len(cleaned_data) >= 2:
                if cleaned_data[-1] > 0x7E or cleaned_data[-2] > 0x7E:
                    cleaned_data.pop()
                    cleaned_data.pop()
                    backtrack_count = 2
                    removed_noise_pairs += 1
            elif len(cleaned_data) == 1 and cleaned_data[-1] > 0x7E:
                cleaned_data.pop()
                backtrack_count = 1
                removed_isolated += 1
            
            i += header_length
            continue
        
        # 獨立的 Non-ASCII byte (保留換行符)
        if data_stream[i] > 0x7E and data_stream[i] not in [0x0D, 0x0A]:
            removed_isolated += 1
            i += 1
            continue
        
        # 保留正常 byte
        cleaned_data.append(data_stream[i])
        i += 1
    
    return cleaned_data, {
        'packet_headers': removed_packet_headers,
        'noise_pairs': removed_noise_pairs,
        'isolated': removed_isolated
    }

def reconstruct_and_compare():
    print("=" * 80)
    print(" Android Serial Log 完整重建與比對")
    print("=" * 80)
    print()
    
    # 1. 解析 Serial Log
    serial_log_path = 'tree_project/Tree_app_equipment_info/serial_20251125_200547(DATA_2).txt'
    ground_truth_path = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    print("[Step 1] 解析 Serial Log...")
    data_stream = parse_serial_log_correctly(serial_log_path)
    print(f"  原始 byte stream: {len(data_stream)} bytes")
    print()
    
    # 2. 套用過濾器
    print("[Step 2] 套用 v13.1 Byte-Level 過濾器...")
    cleaned_data, stats = apply_v13_1_filter(data_stream)
    print(f"  清洗後: {len(cleaned_data)} bytes")
    print(f"  移除:")
    print(f"    - PacketLogger 封包頭: {stats['packet_headers']} 個 (共 {stats['packet_headers']*3} bytes)")
    print(f"    - 配對雜訊: {stats['noise_pairs']} 對 (共 {stats['noise_pairs']*2} bytes)")
    print(f"    - 獨立 Non-ASCII: {stats['isolated']} 個")
    print(f"  總計移除: {len(data_stream) - len(cleaned_data)} bytes")
    print()
    
    # 3. 解碼並重建 CSV
    print("[Step 3] 解碼並重建 CSV...")
    try:
        csv_text = bytes(cleaned_data).decode('utf-8', errors='ignore')
    except:
        csv_text = bytes(cleaned_data).decode('latin-1', errors='ignore')
    
    # String-Level 白名單過濾
    csv_text = re.sub(r'[^0-9A-Z\.\;\-\r\n\$\#]', '', csv_text)
    
    # 提取數據行
    reconstructed_lines = []
    for line in csv_text.split('\n'):
        line = line.strip()
        if line.startswith('$'):
            reconstructed_lines.append(line)
    
    print(f"  重建數據: {len(reconstructed_lines)} 筆")
    print()
    
    # 4. 讀取官方 App 輸出
    print("[Step 4] 讀取官方 App 輸出...")
    gt_lines = []
    with open(ground_truth_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('$'):
                gt_lines.append(line)
    
    print(f"  官方 App: {len(gt_lines)} 筆")
    print()
    
    # 5. 逐筆比對
    print("[Step 5] 逐筆比對...")
    print("=" * 80)
    
    matches = 0
    differences = []
    
    max_len = min(len(reconstructed_lines), len(gt_lines))
    
    for i in range(max_len):
        if reconstructed_lines[i] == gt_lines[i]:
            matches += 1
        else:
            # 提取 ID 進行標記
            id_match = re.search(r';;;;(\d+);', gt_lines[i])
            record_id = id_match.group(1) if id_match else f"Line_{i+1}"
            
            differences.append({
                'id': record_id,
                'line': i + 1,
                'ours': reconstructed_lines[i],
                'official': gt_lines[i]
            })
    
    accuracy = matches / max_len * 100 if max_len > 0 else 0
    
    print(f"\n準確率: {matches}/{max_len} 筆 ({accuracy:.1f}%)")
    print()
    
    if len(reconstructed_lines) != len(gt_lines):
        print(f"WARNING: 筆數不一致")
        print(f"  我們: {len(reconstructed_lines)} 筆")
        print(f"  官方: {len(gt_lines)} 筆")
        print(f"  差異: {abs(len(reconstructed_lines) - len(gt_lines))} 筆")
        print()
    
    if differences:
        print(f"\n差異列表 (共 {len(differences)} 筆，顯示前 20 筆):")
        print("-" * 80)
        
        for diff in differences[:20]:
            print(f"\nID: {diff['id']} (Line {diff['line']})")
            print(f"  我們:")
            print(f"    {diff['ours'][:120]}")
            print(f"  官方:")
            print(f"    {diff['official'][:120]}")
            
            # 找出具體差異位置
            ours = diff['ours']
            official = diff['official']
            fields_ours = ours.split(';')
            fields_official = official.split(';')
            
            for idx, (f1, f2) in enumerate(zip(fields_ours, fields_official)):
                if f1 != f2:
                    print(f"      欄位 [{idx}]: '{f1}' vs '{f2}'")
        
        if len(differences) > 20:
            print(f"\n  ... 還有 {len(differences) - 20} 筆差異未顯示")
    
    print()
    print("=" * 80)
    
    # 判斷結果
    if accuracy >= 99.5:
        print("\nSTATUS: 100% 成功！可以發布！")
    elif accuracy >= 90:
        print(f"\nSTATUS: 接近成功 ({accuracy:.1f}%)，還有少數差異需處理")
    else:
        print(f"\nSTATUS: 需要進一步分析 ({accuracy:.1f}%)")
    
    print("=" * 80)
    
    return accuracy, differences

if __name__ == "__main__":
    reconstruct_and_compare()






