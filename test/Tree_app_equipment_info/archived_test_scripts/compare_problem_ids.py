import csv

# 讀取比對
with open('DATA_2.CSV', 'r', encoding='utf-8') as f:
    official = {row[6]: row for row in csv.reader(f, delimiter=';') if len(row) > 6 and row[6]}

with open('PC_RECEIVED_V135.CSV', 'r', encoding='utf-8') as f:
    ours = {row[6]: row for row in csv.reader(f, delimiter=';') if len(row) > 6 and row[6]}

# 問題 ID 詳細分析
problem_ids = ['10071', '10087', '10092']

for pid in problem_ids:
    print(f'=== ID {pid} ===')
    o = official.get(pid, [])
    m = ours.get(pid, [])
    
    if o and m:
        print(f'UTC [19]: 官方="{o[19]}" (len={len(o[19])}) vs 我們="{m[19]}" (len={len(m[19])})')
        print(f'LON [14]: 官方="{o[14]}" vs 我們="{m[14]}"')
        if '.' in o[14]:
            print(f'  官方小數: {o[14].split(".")[1]} (len={len(o[14].split(".")[1])})')
        if '.' in m[14]:
            print(f'  我們小數: {m[14].split(".")[1]} (len={len(m[14].split(".")[1])})')
        print(f'HD [24]: 官方="{o[24]}" vs 我們="{m[24]}"')
    print()

# 額外：檢查是否有其他欄位的差異
print('=== 完整欄位差異 ===')
for pid in problem_ids:
    o = official.get(pid, [])
    m = ours.get(pid, [])
    if o and m:
        diffs = []
        for i in range(min(len(o), len(m))):
            if o[i] != m[i]:
                diffs.append(f'[{i}]: "{o[i]}" vs "{m[i]}"')
        print(f'ID {pid}: {len(diffs)} 差異')
        for d in diffs:
            print(f'  {d}')
