# Agent 下拉選單顯示格式修改 - 分析與實作計畫

**文件建立日期**: 2025-11-20
**專案**: SOPL Frontend
**需求**: 將 Agent 下拉選單顯示格式從 `Org Name` 改為 `Org Name (Org Code)`

---

## 目錄

1. [需求說明](#需求說明)
2. [影響範圍分析](#影響範圍分析)
3. [技術實作細節](#技術實作細節)
4. [詳細實作計畫](#詳細實作計畫)
5. [測試計畫](#測試計畫)
6. [風險評估與注意事項](#風險評估與注意事項)
7. [回滾方案](#回滾方案)

---

## 需求說明

### 現況
目前 Agent 下拉選單只顯示組織名稱（Org Name）：
```
ORIENT EXPRESS CONTAINER CO., LTD
ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC)
```

### 目標
修改為顯示「組織名稱 (組織代碼)」格式：
```
ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)
ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC) (ORIEXPPVG2)
```

### 業務價值
- 提升使用者辨識效率：可同時看到名稱與代碼
- 減少選擇錯誤：代碼提供額外識別資訊
- 符合系統其他下拉選單的一致性設計模式

---

## 影響範圍分析

### 修改檔案

**只需修改一個共用元件檔案**：

```
📁 /home/mabelmis/sopl/frontend/release/src/v2components/common/OecSelectTagFilter.js
```

### 影響的模組與頁面

此修改會影響所有使用 `OecSelectTagFilter` 元件的 Agent/Organization 選擇功能：

#### 1. **PL Module (Profit Share - 利潤分享)**
- **頁面**: `ProfitShareList` (利潤分享列表)
- **位置**: 搜尋條件列的 "Agent" 篩選器
- **檔案路徑**:
  - `src/page/ProfitShareList/index.js`
  - `src/pageComponents/ProfitShareList/SearchBar/index.js`

#### 2. **SO Module (Shipping Order - 運輸訂單)**
- **頁面**: `InstructionList` (指示列表)
- **位置**: 搜尋條件列的 "Organization" 篩選器
- **檔案路徑**:
  - `src/pageComponents/InstructionList/SearchBar/index.js`

- **頁面**: `InstructionDetail` (指示詳情)
- **位置**: "Copy From" 對話框中的 Organization 選擇器
- **檔案路徑**:
  - `src/pageComponents/InstructionDetail/modal/CopyFromSearchBar.js`

#### 3. **IC Module (Import Charges - 進口費用)**
- **頁面**: `ImportChargesList` (進口費用列表)
- **位置**: 搜尋條件列的 "Organization" 篩選器
- **檔案路徑**:
  - `src/pageComponents/ImportChargesList/SearchBar/index.js`

### 元件依賴關係圖

```
OecSelectTagFilter.js (共用元件) ⭐ 修改點
│
├── AgentCheck.js (v2components/filter/)
│   └── ProfitShareList/SearchBar
│       └── 使用者看到的 "Agent" 篩選器
│
└── TargetMultiSelect.js (v2components/filter/)
    └── OrganizationCheck.js (v2components/filter/)
        ├── InstructionList/SearchBar
        │   └── "Organization" 篩選器
        ├── ImportChargesList/SearchBar
        │   └── "Organization" 篩選器
        └── InstructionDetail/CopyFromSearchBar
            └── Copy From 對話框的 "Organization" 選擇
```

### 資料流說明

```
1. 使用者輸入搜尋關鍵字 (至少 3 個字元)
   ↓
2. OecSelectTagFilter.promiseOptions() 被觸發
   ↓
3. fetchFilter() 呼叫 postSearchMasterCode API
   ↓
4. API 回傳資料格式:
   {
     body: [
       { code: "ORIEXPPVG", value: "ORIENT EXPRESS CONTAINER CO., LTD" },
       { code: "ORIEXPPVG2", value: "ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC)" }
     ]
   }
   ↓
5. 資料處理 (目前 Line 70-73):
   data.body.forEach((e, index) => {
     options.push({
       label: e.value,        // ← 只顯示名稱
       value: e.code
     });
   });
   ↓
6. 下拉選單顯示 label 欄位給使用者
```

---

## 技術實作細節

### 修改位置

**檔案**: `src/v2components/common/OecSelectTagFilter.js`
**行數**: Line 70-73

### 修改前的程式碼

```javascript
const fetchFilter = async (inputValue) => {
  console.log("@@@@SelectTagInputFilter fetchFilter", inputValue);

  const params = fetchSelectionParams();
  console.log("@@@@@Fetch postSearchMasterCode:", params);
  params.body.keyword = inputValue;
  const data = await getOptionsData.mutateAsync(params);
  const options = [];
  data.body.forEach((e, index) => {
    console.log("e.label=", e.label);
    options.push({ label: e.value, value: e.code });  // ← Line 72: 目前只顯示 e.value
  });
  console.log("@@@before setOptions, options = ", options, data.body);
  return options;
};
```

### 修改後的程式碼

```javascript
const fetchFilter = async (inputValue) => {
  console.log("@@@@SelectTagInputFilter fetchFilter", inputValue);

  const params = fetchSelectionParams();
  console.log("@@@@@Fetch postSearchMasterCode:", params);
  params.body.keyword = inputValue;
  const data = await getOptionsData.mutateAsync(params);
  const options = [];
  data.body.forEach((e, index) => {
    console.log("e.label=", e.label);
    // 修改: 顯示 "Org Name (Org Code)" 格式
    options.push({
      label: `${e.value} (${e.code})`,  // ← 新增 Org Code
      value: e.code
    });
  });
  console.log("@@@before setOptions, options = ", options, data.body);
  return options;
};
```

### 變更說明

| 項目 | 修改前 | 修改後 |
|------|--------|--------|
| **顯示內容** | `e.value` | `` `${e.value} (${e.code})` `` |
| **範例顯示** | `ORIENT EXPRESS CONTAINER CO., LTD` | `ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)` |
| **實際儲存值** | `e.code` (不變) | `e.code` (不變) |
| **API 資料結構** | 不需變更 | 不需變更 |
| **後端影響** | 無 | 無 |

### 關鍵技術點

1. **Template Literal (樣板字串)**:
   - 使用 ES6 的 `` `${variable}` `` 語法
   - 確保變數插值正確執行

2. **資料來源**:
   - `e.value`: 組織名稱 (String)
   - `e.code`: 組織代碼 (String)
   - 兩者都由 `postSearchMasterCode` API 回傳

3. **顯示 vs 儲存**:
   - `label`: 使用者看到的文字（修改點）
   - `value`: 實際儲存的資料（不變）

---

## 詳細實作計畫

### Phase 1: 準備階段 (5 分鐘)

#### Step 1.1: 建立 Git 分支
```bash
cd /home/mabelmis/sopl/frontend/release
git checkout -b feature/SOPL-XXXX-agent-dropdown-format
git status
```

#### Step 1.2: 備份原始檔案
```bash
cp src/v2components/common/OecSelectTagFilter.js \
   src/v2components/common/OecSelectTagFilter.js.backup
```

#### Step 1.3: 確認開發環境
```bash
# 確認 Node.js 版本
node --version

# 確認依賴已安裝
npm list --depth=0
```

---

### Phase 2: 程式碼修改 (5 分鐘)

#### Step 2.1: 開啟檔案編輯
使用 Claude Code 或 IDE 開啟：
```
/home/mabelmis/sopl/frontend/release/src/v2components/common/OecSelectTagFilter.js
```

#### Step 2.2: 定位修改位置
- **檔案**: `OecSelectTagFilter.js`
- **函式**: `fetchFilter`
- **行數**: Line 72

#### Step 2.3: 執行修改

**原始程式碼** (Line 72):
```javascript
options.push({ label: e.value, value: e.code });
```

**修改為**:
```javascript
options.push({ label: `${e.value} (${e.code})`, value: e.code });
```

#### Step 2.4: 儲存檔案
確認修改後儲存檔案

---

### Phase 3: 本地測試 (20 分鐘)

#### Step 3.1: 啟動開發伺服器
```bash
cd /home/mabelmis/sopl/frontend/release
npm start
```
等待啟動完成，預期在 `http://localhost:3000`

#### Step 3.2: 測試 ProfitShareList (PL Module)
1. 瀏覽器開啟 `http://localhost:3000/profitShareList`
2. 點擊 "Agent" 篩選器
3. 在 "SEN Agent" 輸入框輸入關鍵字 (如: "ORI")
4. **驗證點**:
   - ✅ 下拉選單顯示格式為 `組織名稱 (組織代碼)`
   - ✅ 選取後功能正常運作
   - ✅ 搜尋結果能正確顯示

#### Step 3.3: 測試 InstructionList (SO Module)
1. 開啟 `http://localhost:3000/instructionList`
2. 點擊 "Organization" 篩選器
3. 輸入關鍵字測試
4. **驗證點**:
   - ✅ 格式正確顯示
   - ✅ 多選功能正常
   - ✅ Apply/Clear 按鈕正常

#### Step 3.4: 測試 ImportChargesList (IC Module)
1. 開啟 `http://localhost:3000/importChargesList`
2. 測試 "Organization" 篩選器
3. **驗證點**: 同 Step 3.3

#### Step 3.5: 測試 InstructionDetail Copy From
1. 開啟任一 Instruction Detail 頁面
2. 點擊 "Copy From" 功能
3. 測試 Organization 選擇器
4. **驗證點**:
   - ✅ 對話框中的選擇器格式正確
   - ✅ Copy 功能不受影響

#### Step 3.6: 跨瀏覽器測試 (選擇性)
- Chrome/Edge: 主要測試
- Firefox: 次要測試
- Safari (如有 Mac): 選擇性測試

---

### Phase 4: 程式碼檢查 (10 分鐘)

#### Step 4.1: 執行 Lint 檢查
```bash
npm run lint
```
預期結果: 無 ESLint 錯誤

#### Step 4.2: 執行格式化檢查
```bash
npm run format
```
確保程式碼符合 Prettier 規範

#### Step 4.3: 檢查 Console 警告
開啟瀏覽器 DevTools Console，確認:
- ❌ 無 React 警告
- ❌ 無 API 錯誤
- ❌ 無未處理的 Promise rejection

---

### Phase 5: 建立 Pull Request (10 分鐘)

#### Step 5.1: Commit 變更
```bash
git add src/v2components/common/OecSelectTagFilter.js
git commit -m "SOPL-XXXX feat: Add Org Code to Agent dropdown display format

- Modify OecSelectTagFilter.js to display 'Org Name (Org Code)'
- Affects PL, SO, IC modules' Agent/Organization filters
- Improves user identification with both name and code visible

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"
```

#### Step 5.2: Push 到遠端
```bash
git push -u origin feature/SOPL-XXXX-agent-dropdown-format
```

#### Step 5.3: 建立 Pull Request
```bash
gh pr create \
  --title "SOPL-XXXX feat: Add Org Code to Agent dropdown display format" \
  --body "$(cat <<'EOF'
## Summary
- Modified Agent/Organization dropdown to display format: `Org Name (Org Code)`
- Single file change in shared component `OecSelectTagFilter.js`
- Improves user experience by showing both organization name and code

## Affected Modules
- ✅ **PL Module**: ProfitShareList - Agent filter
- ✅ **SO Module**: InstructionList, InstructionDetail - Organization filter
- ✅ **IC Module**: ImportChargesList - Organization filter

## Changes Made
**File**: `src/v2components/common/OecSelectTagFilter.js`
**Line**: 72
**Change**: `label: e.value` → `label: \`\${e.value} (\${e.code})\``

## Test Plan
- [x] ProfitShareList Agent filter displays correctly
- [x] InstructionList Organization filter works
- [x] ImportChargesList Organization filter works
- [x] InstructionDetail Copy From dialog works
- [x] ESLint passes with no errors
- [x] No console warnings in browser

## Screenshots
[Please add before/after screenshots]

## Backward Compatibility
- ✅ No breaking changes
- ✅ API contract unchanged
- ✅ Saved values (Org Code) remain the same
- ✅ Only display format changed

🤖 Generated with Claude Code
EOF
)" \
  --base dev
```

---

## 測試計畫

### 功能測試矩陣

| 測試項目 | 測試頁面 | 測試步驟 | 預期結果 | 優先級 |
|---------|---------|---------|---------|-------|
| **顯示格式** | ProfitShareList | 點擊 Agent 篩選器，輸入關鍵字 | 下拉選項顯示 `Name (Code)` | P0 |
| **搜尋功能** | ProfitShareList | 輸入組織名稱關鍵字 | 能正確搜尋並顯示 | P0 |
| **選擇功能** | ProfitShareList | 選擇一個 Agent | 能正確選取並顯示在 tag 中 | P0 |
| **多選功能** | InstructionList | 選擇多個 Organization | 可選取多個，Apply 後正確顯示 | P0 |
| **刪除功能** | InstructionList | 刪除已選的 Organization | 能正確移除 | P1 |
| **Clear 功能** | ProfitShareList | 點擊 Clear 按鈕 | 清除所有已選 Agent | P1 |
| **API 查詢** | All | Apply 篩選條件後查詢 | 使用 Org Code 查詢，結果正確 | P0 |
| **Copy From** | InstructionDetail | 開啟 Copy From 對話框 | Organization 選擇器格式正確 | P1 |
| **長文字處理** | All | 選擇名稱很長的組織 | 文字不溢出，顯示正常 | P2 |
| **特殊字元** | All | 搜尋含特殊字元的組織 | 正確顯示括號、逗號等 | P2 |

### 測試案例範例

#### TC-001: ProfitShareList Agent 篩選器顯示格式
- **前置條件**: 登入系統，進入 Profit Share List 頁面
- **步驟**:
  1. 點擊 "Agent" 篩選器按鈕
  2. 在 "SEN Agent" 下拉選單輸入 "ORIENT"
  3. 等待搜尋結果出現
- **預期結果**:
  - 下拉選單顯示: `ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)`
  - 括號中顯示組織代碼
  - 格式一致，無排版錯誤

#### TC-002: InstructionList 多選 Organization
- **前置條件**: 登入系統，進入 Instruction List 頁面
- **步驟**:
  1. 點擊 "Organization" 篩選器
  2. 選擇第一個 Organization type
  3. 搜尋並選擇 2 個不同的組織
  4. 點擊 "Add" 新增第二個條件
  5. 選擇另一個 Organization type 和組織
  6. 點擊 "Apply"
- **預期結果**:
  - 所有選擇的組織都顯示 `Name (Code)` 格式
  - Apply 後查詢條件正確
  - 查詢結果符合篩選條件

#### TC-003: 保存的查詢條件回復
- **前置條件**: 已執行過一次查詢並選擇 Agent
- **步驟**:
  1. 在 ProfitShareList 選擇 Agent 並查詢
  2. 點擊查詢結果進入 Detail 頁面
  3. 點擊麵包屑返回 List 頁面
- **預期結果**:
  - 之前選擇的 Agent 正確回復
  - 顯示格式為 `Name (Code)`
  - 查詢結果與之前一致

### 效能測試

| 測試項目 | 測試方法 | 效能指標 | 備註 |
|---------|---------|---------|------|
| **API 回應時間** | Network DevTools | < 2 秒 | 與修改前相同 |
| **下拉選單渲染** | Performance DevTools | < 100ms | 字串拼接影響極小 |
| **記憶體使用** | Memory DevTools | 無顯著增加 | 字串長度增加約 10-20 字元 |

---

## 風險評估與注意事項

### 高風險項目 (需特別注意)

#### 1. 顯示寬度問題
**風險**: 新格式較長，可能造成 UI 排版問題

**影響**:
- 下拉選單可能需要更寬的空間
- 已選擇的 Tag 可能顯示不完整

**緩解方案**:
- 測試時檢查 UI 在不同螢幕寬度下的顯示
- 如需要，調整 CSS `max-width` 或使用 `text-overflow: ellipsis`
- 可考慮在 Tag 中只顯示 Code，tooltip 顯示完整名稱

#### 2. 資料完整性
**風險**: 若 API 回傳的 `code` 或 `value` 為 null/undefined

**影響**:
- 顯示可能為 `undefined (undefined)` 或錯誤格式

**緩解方案**:
```javascript
// 建議加入防禦性程式碼
options.push({
  label: e.value && e.code
    ? `${e.value} (${e.code})`
    : e.value || e.code || 'Unknown',
  value: e.code
});
```

#### 3. 括號衝突
**風險**: 組織名稱本身可能已包含括號

**範例**: `ORIENT EXPRESS (ASIA) LTD` → `ORIENT EXPRESS (ASIA) LTD (ORIEXPASIA)`

**影響**:
- 可能造成使用者混淆

**緩解方案**:
- 目前格式已有類似情況: `ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC)`
- 保持現有格式，使用者應能理解最後的括號為 Code
- 如需區分，可考慮使用其他符號: `Name | Code` 或 `Name - [Code]`

### 中風險項目

#### 4. 已保存的查詢條件
**風險**: 使用者之前保存的查詢條件可能顯示不一致

**影響**:
- 新舊格式混合顯示（機率低，因為保存的是 code 而非 label）

**緩解方案**:
- 已保存的是 `value` (code)，不是 `label`
- 重新載入時會重新組合 label，應無問題

#### 5. 特殊字元處理
**風險**: 組織名稱或代碼可能包含特殊字元

**影響**:
- 顯示錯誤或被 escape

**緩解方案**:
- Template literal 會自動處理大部分特殊字元
- 測試時驗證特殊字元的組織

### 低風險項目

#### 6. 效能影響
**風險**: 字串拼接可能影響效能

**影響**:
- 極小，字串拼接在現代 JavaScript 引擎中非常快

**緩解方案**:
- 不需特別處理

#### 7. 國際化 (i18n)
**風險**: 括號符號在不同語系可能不同

**影響**:
- 目前系統為英文介面，影響低

**緩解方案**:
- 保持現有實作
- 未來如需支援多語系，可從 i18n 檔案讀取格式樣板

### 相依性檢查

| 項目 | 檢查點 | 風險等級 |
|------|-------|---------|
| **React 版本** | 18.2.0 - Template literal 完全支援 | 低 |
| **瀏覽器支援** | ES6 Template literal - 所有現代瀏覽器支援 | 低 |
| **API Contract** | 只使用現有欄位，無新增要求 | 低 |
| **資料庫** | 無影響 (只改顯示) | 無 |
| **後端** | 無影響 | 無 |

---

## 回滾方案

### 快速回滾步驟

#### 方案 1: Git Revert (推薦)
```bash
# 1. 找到 commit hash
git log --oneline -5

# 2. Revert commit
git revert <commit-hash>

# 3. Push
git push origin feature/SOPL-XXXX-agent-dropdown-format
```

#### 方案 2: 直接修改
恢復原始程式碼:
```javascript
// Line 72 改回
options.push({ label: e.value, value: e.code });
```

#### 方案 3: 使用備份檔案
```bash
cp src/v2components/common/OecSelectTagFilter.js.backup \
   src/v2components/common/OecSelectTagFilter.js
```

### 回滾決策點

**何時需要回滾?**
- ✅ UI 顯示嚴重錯誤，影響使用者操作
- ✅ 效能明顯下降 (unlikely)
- ✅ 發現資料錯誤或遺失
- ✅ 產品/業務決定不採用新格式

**何時不需要回滾?**
- ❌ 小的格式調整需求 (直接修改即可)
- ❌ 使用者反饋想調整括號位置 (修改格式即可)

---

## 後續優化建議

### Short-term (1-2 週內)
1. **收集使用者反饋**
   - 觀察 Help Desk tickets
   - 詢問 Key Users 使用感受
   - 調查是否有格式偏好

2. **UI 微調** (如需要)
   - 調整下拉選單寬度
   - 優化長文字顯示 (ellipsis)
   - 調整 Tag 顯示方式

### Mid-term (1 個月內)
1. **一致性檢查**
   - 檢查系統其他下拉選單是否需要統一格式
   - 建立 UI Style Guide 統一規範

2. **效能監控**
   - 使用 Application Performance Monitoring 工具
   - 監控頁面載入時間變化

### Long-term (未來考慮)
1. **可配置化**
   - 允許使用者在設定中選擇顯示格式
   - 選項: "Name only", "Name (Code)", "Code - Name"

2. **智慧顯示**
   - 根據螢幕寬度自動調整顯示格式
   - 手機版只顯示 Code，Desktop 顯示完整

---

## 相關資源

### 文件連結
- 專案 README: `/home/mabelmis/sopl/frontend/release/README.md`
- CLAUDE.md: `/home/mabelmis/sopl/frontend/release/CLAUDE.md`
- Component Guidelines: 參考 CLAUDE.md 中的 Component Development Guidelines

### API 文件
- `postSearchMasterCode` API: `src/api/api_search.js`
- API 文件: `doc/20250607-sopl-api-docs.json`

### 相關元件
- `SelectTagFilter`: `@oec/oec-components` package
- `AgentCheck`: `src/v2components/filter/AgentCheck.js`
- `OrganizationCheck`: `src/v2components/filter/OrganizationCheck.js`
- `TargetMultiSelect`: `src/v2components/filter/TargetMultiSelect.js`

### 開發工具
- Node.js: 專案使用版本
- NPM: `--legacy-peer-deps` flag 必要
- Git: 版本控制
- Chrome DevTools: 測試與除錯

---

## 附錄

### A. 修改前後對比

#### 修改前
```javascript
// OecSelectTagFilter.js Line 72
options.push({ label: e.value, value: e.code });
```

**顯示結果**:
```
下拉選單:
  ORIENT EXPRESS CONTAINER CO., LTD
  ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC)

已選擇 Tag:
  [ORIENT EXPRESS CONTAINER CO., LTD] [x]
```

#### 修改後
```javascript
// OecSelectTagFilter.js Line 72
options.push({ label: `${e.value} (${e.code})`, value: e.code });
```

**顯示結果**:
```
下拉選單:
  ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)
  ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC) (ORIEXPPVG2)

已選擇 Tag:
  [ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)] [x]
```

### B. 測試資料範例

```javascript
// API Response 範例
{
  status: "SUCCESS",
  body: [
    {
      code: "ORIEXPPVG",
      value: "ORIENT EXPRESS CONTAINER CO., LTD"
    },
    {
      code: "ORIEXPPVG2",
      value: "ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC)"
    },
    {
      code: "OECSHANGH",
      value: "OEC SHANGHAI CO., LTD"
    }
  ]
}

// 處理後的 options
[
  {
    label: "ORIENT EXPRESS CONTAINER CO., LTD (ORIEXPPVG)",
    value: "ORIEXPPVG"
  },
  {
    label: "ORIENT EXPRESS CONTAINER CO.,LTD (SH1-OEC) (ORIEXPPVG2)",
    value: "ORIEXPPVG2"
  },
  {
    label: "OEC SHANGHAI CO., LTD (OECSHANGH)",
    value: "OECSHANGH"
  }
]
```

### C. 常見問題 FAQ

**Q1: 為什麼只需要改一個檔案?**
A1: 因為 `OecSelectTagFilter.js` 是一個共用元件 (shared component)，所有 Agent/Organization 選擇器都使用它。改一次就能套用到所有地方。

**Q2: 修改會影響已保存的查詢條件嗎?**
A2: 不會。系統保存的是 `value` (Org Code)，不是 `label` (顯示文字)。重新載入時會根據新格式重新組合顯示文字。

**Q3: 如果組織名稱本身就有括號怎麼辦?**
A3: 會顯示為巢狀括號，例如: `ORIENT EXPRESS (ASIA) LTD (ORIEXPASIA)`。使用者應能理解最後的括號為代碼。

**Q4: 修改後效能會變差嗎?**
A4: 不會。字串拼接 (`template literal`) 在現代 JavaScript 引擎中效能極佳，影響可忽略不計。

**Q5: 需要通知後端團隊嗎?**
A5: 不需要。這是純前端顯示層的修改，不影響 API contract 或資料結構。

**Q6: 如果使用者不喜歡新格式怎麼辦?**
A6: 可以快速回滾 (參考「回滾方案」章節)，或根據反饋調整格式 (如改用 `-` 或 `|` 分隔)。

**Q7: 這個修改會影響打印報表嗎?**
A7: 不會。報表使用的是實際資料 (Org Code)，不是下拉選單的顯示文字。

**Q8: 需要更新測試案例嗎?**
A8: 如果有 E2E 測試檢查下拉選單文字，需要更新。單元測試通常不受影響 (測試的是 value 而非 label)。

---

## 簽核

| 角色 | 姓名 | 日期 | 簽名 |
|------|------|------|------|
| **開發者** | | | |
| **Code Reviewer** | | | |
| **QA** | | | |
| **Product Owner** | | | |

---

**文件版本**: v1.0
**最後更新**: 2025-11-20
**下次審查日期**: 實作完成後一週

---

*本文件由 Claude Code 協助產生*
