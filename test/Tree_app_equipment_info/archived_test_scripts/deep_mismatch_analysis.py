import re
import sys

def deep_mismatch_analysis(log_path, gt_path):
    """深度分析造成數據差異的具體 Hex 序列"""
    
    print("=" * 70)
    print(" Deep Mismatch Analysis - Finding Noise Characters")
    print("=" * 70)
    
    # 讀取 Log
    content = ""
    for enc in ['utf-16', 'utf-8']:
        try:
            with open(log_path, 'r', encoding=enc) as f:
                content = f.read()
            break
        except:
            continue
    
    # 讀取 Ground Truth
    with open(gt_path, 'r', encoding='utf-8') as f:
        gt_lines = [l.strip() for l in f.readlines() if l.strip() and l.startswith('$')]
    
    # 建立 Ground Truth Map
    gt_map = {}
    for line in gt_lines:
        parts = line.split(';')
        if len(parts) > 6:
            rec_id = parts[6].strip()
            if rec_id:
                gt_map[rec_id] = line
    
    print(f"[OK] Loaded {len(gt_map)} Ground Truth records")
    
    # 分析 Log 中的 [BLE RAW] 與 [BLE CLEANED] 配對
    # 我們要找出「被保留但不該保留」的字元
    
    raw_cleaned_pairs = []
    lines = content.splitlines()
    
    for i, line in enumerate(lines):
        if "[BLE RAW]" in line:
            raw_hex = line.split("[BLE RAW]")[1].strip()
            # 找下一行的 CLEANED
            if i+1 < len(lines) and "[BLE CLEANED]" in lines[i+1]:
                cleaned_part = lines[i+1].split("[BLE CLEANED]")[1].strip()
                # 檢查是否有過濾動作 (有 ->)
                if '->' in cleaned_part:
                    parts = cleaned_part.split('->')
                    if len(parts) == 2:
                        raw_cleaned_pairs.append({
                            'hex': raw_hex,
                            'before': parts[0].strip('"'),
                            'after': parts[1].strip('"'),
                            'line_num': i+1
                        })
    
    print(f"[OK] Found {len(raw_cleaned_pairs)} noise cleaning events\n")
    
    # 統計哪些「看起來合法」的字元其實是雜訊
    suspicious_chars = {}
    
    for pair in raw_cleaned_pairs:
        before = pair['before']
        after = pair['after']
        
        # 找出被移除的字元
        # 簡單做法：找出 before 中存在但 after 中不存在的字元
        removed = set(before) - set(after)
        
        for char in removed:
            # 檢查這個字元是否在「合法範圍」內（A-Z, 0-9）
            # 如果是，表示它可能是「偽裝的雜訊」
            if char.isalnum() or char in ['.', ';', '-', '$', '#']:
                if char not in suspicious_chars:
                    suspicious_chars[char] = 0
                suspicious_chars[char] += 1
    
    print("Suspicious 'Legal-Looking' Noise Characters:")
    print("-" * 70)
    for char, count in sorted(suspicious_chars.items(), key=lambda x: x[1], reverse=True):
        print(f"  '{char}' -> appeared {count} times in noise contexts")
    
    print("\n" + "=" * 70)
    
    # 具體案例分析：找出 ID 10031 的問題
    print("\nCase Study: ID 10031 (GT='1' vs LOG='15')")
    print("-" * 70)
    
    # 在 Log 中搜索包含 "10031" 的 RAW 行
    for i, line in enumerate(lines):
        if "10031" in line and "[BLE RAW]" in line:
            print(f"[Line {i+1}] {line}")
            # 也印出後續的 CLEANED (如果有)
            if i+1 < len(lines) and "[BLE CLEANED]" in lines[i+1]:
                print(f"[Line {i+2}] {lines[i+1]}")
            print()

if __name__ == "__main__":
    log_file = 'tree_project/project_code/frontend/ble_debug_log.txt'
    gt_file = 'tree_project/Tree_app_equipment_info/DATA_2.CSV'
    
    if len(sys.argv) > 2:
        log_file = sys.argv[1]
        gt_file = sys.argv[2]
    
    deep_mismatch_analysis(log_file, gt_file)

