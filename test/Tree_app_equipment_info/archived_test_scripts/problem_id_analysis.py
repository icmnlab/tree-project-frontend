# 問題 ID 的殘留分析
problems = {
    '10071': ('5D 44 CD 00', 'HD: 42] + 44CD00 + .5 → 應該是 4.5'),
    '10087': ('72 39 44 CD 00', 'UTC: 85508 + r9 + 44CD00 → 應該是 85508'),
    '10092': ('1D 44 CD 00', 'LON: 6644 + [1D] + 44CD00 + 72 → 應該是 66472'),
}

print('問題 ID 殘留分析:')
print()
for pid, (hex_seq, desc) in problems.items():
    bytes_seq = bytes.fromhex(hex_seq.replace(' ', ''))
    ascii_repr = ''.join([chr(x) if 0x20 <= x <= 0x7E else f'[{x:02X}]' for x in bytes_seq])
    print(f'ID {pid}:')
    print(f'  Hex: {hex_seq}')
    print(f'  ASCII: {ascii_repr}')
    print(f'  描述: {desc}')
    print()

print('=' * 60)
print()
print('關鍵發現：')
print()
print('1. ID 10071 (HD):')
print('   原始: 6.5;42] D CD 00 .5;6.4')
print('   問題: "2" 和 "]" 是雜訊')
print('   正確: 6.5;4.5;6.4')
print()
print('2. ID 10087 (UTC):')
print('   原始: 85508 r 9 D CD 00 ;1')
print('   問題: "r9" 是雜訊 (0x72 0x39)')
print('   正確: 85508;1')
print()
print('3. ID 10092 (LON):')
print('   原始: 120.536644 [1D] D CD 00 72;E')
print('   問題: "4" 和 "[1D]" 是雜訊')
print('   正確: 120.5366472;E')
print()
print('=' * 60)
print()
print('結論：殘留不只是 [非ASCII]+44CD00，還包括數據流中的錯位')
print('需要更複雜的解碼邏輯！')
