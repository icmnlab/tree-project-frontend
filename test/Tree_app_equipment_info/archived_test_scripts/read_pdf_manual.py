import fitz

pdf_path = 'Manual_Hagloef-Vertex-Laser-Geo2_80-194-02_80-195-02_en_30042024.pdf'
doc = fitz.open(pdf_path)

# 搜尋 CSV 欄位格式相關關鍵字
keywords = ['field', 'column', 'format', 'DATA.CSV', 'separator', 'ID', 'UTM', 'GPS', 'time', 'date']
for i in range(len(doc)):
    page = doc[i]
    text = page.get_text()
    text_lower = text.lower()
    for kw in keywords:
        if kw.lower() in text_lower:
            print(f'=== 第 {i+1} 頁 (包含 "{kw}") ===')
            print(text)
            print()
            break
