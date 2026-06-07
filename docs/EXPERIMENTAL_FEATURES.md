# 實驗功能（程式保留、正式版預設隱藏）

正式現場 APK 預設只顯示儀器整合與樹木資料入口。下列功能程式仍保留，供研究／教授後續開發：

| 功能 | 路由／檔案 | 重新啟用 |
|------|------------|----------|
| AI 助理 | `/ai-chat` | `--dart-define=ENABLE_EXPERIMENTAL_UI=true` |
| 永續報告 | `/ai-sustainability-report` | 同上 |
| 掃描測試 Demo | `ScannerPage` | 同上 |
| 獨立樹種辨識 | `SpeciesIdentificationPage` | 同上（表單內辨識仍可用） |
| V3 同步設定 | `V3ServicesPage` | 同上 |
| 視覺 DBH | `ScannerPage` / `PureVisionDbhService` | 管理後台開啟「研究模式」 |

視覺 DBH 在**手冊合規模式**（預設）下，整合表單已不啟用自動影像 DBH。
