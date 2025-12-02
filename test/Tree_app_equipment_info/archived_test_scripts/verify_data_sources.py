#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
確認數據來源與準確率
"""

def count_data_records(filepath):
    """計算 CSV 中的數據筆數"""
    count = 0
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip().startswith('$'):
                count += 1
    return count

def analyze_files():
    files = [
        ('DATA_2.CSV', '未知來源（請確認）'),
        ('DATA_from_iphone.CSV', 'iPhone 官方 App 輸出'),
        ('reconstructed_from_log.csv', '從 Android BLE Log 重建'),
        ('iphone_1st_reconstructed.csv', '從 iPhone Wireshark 重建（第1次）'),
    ]
    
    print("=" * 80)
    print(" 數據來源分析")
    print("=" * 80)
    print()
    
    for filename, description in files:
        try:
            count = count_data_records(f'tree_project/Tree_app_equipment_info/{filename}')
            print(f"{filename:35} | {count:3} 筆 | {description}")
        except Exception as e:
            print(f"{filename:35} | ERROR | {str(e)}")
    
    print()
    print("=" * 80)
    print()
    print("⚠️  關鍵問題：")
    print()
    print("1. DATA_2.CSV 的來源是什麼？")
    print("   a) 儀器直接連線電腦輸出的「Ground Truth」")
    print("   b) Android App 實際接收並處理後的輸出")
    print("   c) 其他來源？")
    print()
    print("2. DATA_from_iphone.CSV 確定是 iPhone 官方 Haglof Link App 的輸出嗎？")
    print()
    print("3. 如果兩者 100% 相同，為什麼驗證工具顯示只有 84% 準確率？")
    print("   → 可能原因：ble_debug_log.txt 不是最終測試版本")
    print()
    print("=" * 80)

if __name__ == "__main__":
    analyze_files()

