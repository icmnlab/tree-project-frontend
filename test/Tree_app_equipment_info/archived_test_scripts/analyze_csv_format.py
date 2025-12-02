import csv

# 讀取官方資料
with open('DATA_2.CSV', 'r', encoding='utf-8') as f:
    reader = csv.reader(f, delimiter=';')
    rows = list(reader)

# 分析欄位格式規格
print('=== VLGEO2 CSV 欄位格式分析 (基於 336 筆官方資料) ===')
print()

# 欄位名稱對照
field_names = {
    0: 'START ($)',
    1: 'UNKNOWN_1',
    2: 'TYPE (1P/3P/3D/DME)',
    3: 'UNKNOWN_3',
    4: 'UNKNOWN_4',
    5: 'UNKNOWN_5',
    6: 'ID',
    7: 'UNKNOWN_7',
    8: 'EMPTY_8',
    9: 'EMPTY_9',
    10: 'EMPTY_10',
    11: 'EMPTY_11',
    12: 'LATITUDE',
    13: 'N/S',
    14: 'LONGITUDE',
    15: 'E/W',
    16: 'ALTITUDE',
    17: 'HDOP',
    18: 'DATE (DDMMYY)',
    19: 'UTC (HHMMSS)',
    20: 'SEQ',
    21: 'EMPTY_21',
    22: 'EMPTY_22',
    23: 'SD (Slope Distance)',
    24: 'HD (Horizontal Distance)',
    25: 'H (Height)',
    26: 'DIA (Diameter)',
    27: 'PITCH',
    28: 'AZIMUTH',
    29: 'UTM_N',
    30: 'UTM_E',
    31: 'VD (Vertical Dist)',
    32: 'UTM_ZONE'
}

# 分析每個欄位
for idx in range(33):
    values = []
    for row in rows:
        if len(row) > idx and row[6]:  # 有 ID 的有效記錄
            values.append(row[idx])
    
    if values:
        # 統計
        non_empty = [v for v in values if v.strip()]
        lengths = [len(v) for v in non_empty] if non_empty else [0]
        
        name = field_names.get(idx, f'UNKNOWN_{idx}')
        print(f'[{idx:2d}] {name:25s} | 非空: {len(non_empty):3d}/{len(values)} | 長度: {min(lengths)}-{max(lengths)}')
        
        # 對特定欄位顯示範例
        if idx in [14, 19, 24]:
            samples = list(set(non_empty))[:5]
            print(f'     範例: {samples}')

print()
print('=== 關鍵欄位詳細分析 ===')

# UTC [19] 分析
utc_values = []
for row in rows:
    if len(row) > 19 and row[6] and row[19].strip():
        utc_values.append(row[19].strip())

utc_lengths = {}
for v in utc_values:
    l = len(v)
    utc_lengths[l] = utc_lengths.get(l, 0) + 1
print(f'UTC [19] 長度分布: {utc_lengths}')

# LON [14] 小數位分析
lon_decimal_lengths = {}
for row in rows:
    if len(row) > 14 and row[6] and row[14].strip() and '.' in row[14]:
        decimal = row[14].split('.')[1]
        l = len(decimal)
        lon_decimal_lengths[l] = lon_decimal_lengths.get(l, 0) + 1
print(f'LON [14] 小數位長度分布: {lon_decimal_lengths}')

# HD [24] 範圍分析
hd_values = []
for row in rows:
    if len(row) > 24 and row[6] and row[24].strip():
        try:
            hd_values.append(float(row[24]))
        except:
            pass
print(f'HD [24] 範圍: {min(hd_values):.1f} ~ {max(hd_values):.1f}')
