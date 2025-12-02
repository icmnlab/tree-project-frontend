import re
import sys

def analyze_noise_pattern(log_path):
    """深入分析 Log 中的雜訊模式"""
    
    content = ""
    for enc in ['utf-16', 'utf-8']:
        try:
            with open(log_path, 'r', encoding=enc) as f:
                content = f.read()
            break
        except:
            continue
    
    if not content:
        print("Cannot read log")
        return
    
    # 提取所有 [BLE RAW] 和 [BLE CLEANED] 配對
    raw_cleaned_pairs = []
    lines = content.splitlines()
    
    for i, line in enumerate(lines):
        if "[BLE RAW]" in line:
            raw_hex = line.split("[BLE RAW]")[1].strip()
            # 找下一行的 CLEANED
            if i+1 < len(lines) and "[BLE CLEANED]" in lines[i+1]:
                cleaned_part = lines[i+1].split("[BLE CLEANED]")[1].strip()
                raw_cleaned_pairs.append({
                    'raw_hex': raw_hex,
                    'cleaned': cleaned_part
                })
    
    print(f"Found {len(raw_cleaned_pairs)} RAW/CLEANED pairs")
    print("\nAnalyzing noise patterns...")
    print("-" * 60)
    
    # 分析被過濾掉的內容
    noise_patterns = {}
    
    for pair in raw_cleaned_pairs[:100]:  # 分析前 100 對
        raw_hex = pair['raw_hex']
        cleaned = pair['cleaned']
        
        # 如果 CLEANED 包含 '->', 表示有東西被過濾掉
        if '->' in cleaned:
            parts = cleaned.split('->')
            if len(parts) == 2:
                before = parts[0].strip('"')
                after = parts[1].strip('"')
                
                # 計算被移除的部分
                if before and after:
                    # 找出差異
                    removed = before.replace(after, '')
                    if removed:
                        # 從 HEX 推導原始 bytes
                        try:
                            hex_bytes = [int(h, 16) for h in raw_hex.split() if len(h)==2]
                            # 尋找可能的雜訊模式
                            for j in range(len(hex_bytes)-2):
                                seq = f"{hex_bytes[j]:02X} {hex_bytes[j+1]:02X} {hex_bytes[j+2]:02X}"
                                # 檢查是否為 non-ASCII 序列
                                if hex_bytes[j] > 0x7E or hex_bytes[j+1] > 0x7E or hex_bytes[j+2] > 0x7E:
                                    if seq not in noise_patterns:
                                        noise_patterns[seq] = 0
                                    noise_patterns[seq] += 1
                        except:
                            pass
    
    # 排序並輸出最常見的雜訊模式
    print("\nTop Noise Patterns (Hex Sequences):")
    sorted_patterns = sorted(noise_patterns.items(), key=lambda x: x[1], reverse=True)
    for pattern, count in sorted_patterns[:20]:
        print(f"  {pattern} -> appeared {count} times")
    
    print("-" * 60)

if __name__ == "__main__":
    log_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    if len(sys.argv) > 1:
        log_file = sys.argv[1]
    analyze_noise_pattern(log_file)

