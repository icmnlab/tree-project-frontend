# 分析殘留 bytes 的模式
residuals = [
    '3b047c',  # ;[04]|
    '32ed79',  # 2[ED]y
    '38ee27',  # 8[EE]'
    '0a3441',  # [0A]4A
    '386dd8',  # 8m[D8]
    '2e17f8',  # .[17][F8]
    '3b8b3d',  # ;[8B]=
    '3b8a5e',  # ;[8A]^
    '35df58',  # 5[DF]X
    '3178ff',  # 1x[FF]
]

print('殘留 bytes 分析:')
print('模式：[正常CSV字符] + [非ASCII] + [可能是正常字符]')
print()
for r in residuals:
    b = bytes.fromhex(r)
    analysis = []
    for i, x in enumerate(b):
        char = chr(x) if 0x20 <= x <= 0x7E else f'[{x:02X}]'
        is_csv = chr(x) in '0123456789.;-+NSEW$\r\n' if 0x20 <= x <= 0x7E else False
        analysis.append(f'{char}(csv={is_csv})')
    print(f'  {r}: {" | ".join(analysis)}')

print()
print('結論：')
print('殘留模式 = [1 個正常 CSV 字符] + [1 個非 ASCII byte] + [1 個任意 byte]')
print('這表示：前一個封包的最後 1 byte + 2 bytes 的校驗/填充')
