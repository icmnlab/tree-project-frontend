# 專案開發工作流程規範 (Project Development Workflow Rules)

> 📅 建立日期：2025-12-13
> 🎯 目的：確保開發品質、兼容性與可維護性

為確保開發品質與維護性，所有開發工作必須嚴格遵守以下流程：

## 1. 前置準備 (Preparation)

1.  **文件閱讀 (Document Review)**
    *   在開始任何工作前，必須閱讀相關的技術文件、規劃書 (如 `V3_DEVELOPMENT_PLAN.md`, `DEVELOPMENT_PLAN.md`)。
    *   若涉及計算公式或科學數據，必須閱讀學術參考文獻 (`ACADEMIC_REFERENCES.md`)。
    *   確認了解當前任務在整體架構中的位置與目的。

2.  **工作規劃 (Planning)**
    *   工作文件 (如 Todo List) 必須包含接下來的詳細步驟。
    *   明確定義未來目的與回顧之前的進度。
    *   規劃測試流程或程式測試代碼。

## 2. 開發原則 (Development Principles)

3.  **兼容性優先 (Compatibility First)**
    *   **嚴禁**大規模刪除現有代碼。
    *   所有修改必須保持向後兼容 (Backward Compatibility)，確保舊版 APK 功能仍能正常運作。
    *   若需棄用舊功能，必須採並行策略 (Deprecation Strategy)，直到舊版完全淘汰。

4.  **全面理解 (Comprehensive Understanding)**
    *   修改代碼前，必須閱讀並理解所有相關的檔案（包含前端與後端）。
    *   確認數據流向 (Data Flow) 與依賴關係 (Dependencies)。

5.  **小步迭代 (Iterative Development)**
    *   一個部分一個部分修改，避免一次性的大規模重構。
    *   代碼中應包含 Debug 用的輸出 (如 `debugPrint`)，以便快速定位問題。

## 3. 測試與驗證 (Testing & Verification)

6.  **即時測試 (Immediate Testing)**
    *   改完一個小部分立即跑測試。
    *   **測試通過後**才能進行下一個部分。

7.  **確保準確度 (Accuracy & Credibility)**
    *   涉及數據計算、科學公式的功能，必須上網查證或參考學術文獻。
    *   確保功能的準確度與可信度，不可猜測。

## 4. 收尾與交接 (Completion & Handover)

8.  **文件更新 (Documentation Update)**
    *   每完成一部分工作，必須更新相關文件 (如 `README.md`, `DEVELOPMENT_PLAN.md`)。
    *   記錄已解決的問題與尚待解決的 BUG。

9.  **交接準備 (Handover Preparation)**
    *   工作完成後，檢查文件內容，確保下一階段的 Agent 能順利接手。
    *   寫下明確的下一步工作指引。

10. **最終檢查 (Final Verification)**
    *   仔細檢查所有修改是否完美實現功能。
    *   確認沒有破壞任何既有的功能 (Regression Check)。

---

## 特別注意事項 (Special Notes)

*   **API 統一性**：所有後端呼叫必須透過 `ApiService` 或專屬 Service (如 `TreeService`)，禁止在 UI 層直接使用 `http` 套件。
*   **安全性**：前端不得儲存敏感金鑰，所有權限驗證邏輯需在後端執行。
*   **成本控制**：設計架構時需考慮 Render 成本與學生預算，優先選擇高性價比方案。
