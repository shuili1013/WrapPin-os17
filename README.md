<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/WrapPin-AppIcon-Dark.png">
    <source media="(prefers-color-scheme: light)" srcset="Design/WrapPin-AppIcon-Light.png">
    <img src="Design/WrapPin-AppIcon-Light.png" width="128" height="128" alt="WrapPin 圖示">
  </picture>
</p>

<h1 align="center">WrapPin · iOS 17 分支</h1>

<p align="center">
  Forked from <a href="https://github.com/suversal/WrapPin"><strong>suversal/WrapPin</strong></a>
  （原始專案：Sean Howarth 的 <a href="https://github.com/seanhowarthdev/Roam-Control">Roam Control</a>）
</p>

<p align="center">
  <strong>目前版本：</strong>1.0.22（Build 78） · <strong>最低系統：</strong>iOS 17.4
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.4%2B-brightgreen" alt="iOS 17.4+">
  <img src="https://img.shields.io/badge/Live%20Activity-%E6%94%AF%E6%8F%B4-blue" alt="Live Activity">
  <img src="https://img.shields.io/badge/UI-SwiftUI-orange" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-PolyForm%20NC%201.0.0-blue" alt="PolyForm Noncommercial 1.0.0">
</p>

<p align="center">
  <a href="https://github.com/shuili1013/WrapPin-os17/releases/latest"><strong>下載最新版</strong></a> ·
  <a href="https://github.com/shuili1013/WrapPin-os17/issues">回報問題</a>
</p>

> 請只在你擁有並控制的裝置上使用。不要用來欺騙他人、偽造證據、規避安全限制，或違反第三方服務的規則。

這是 [suversal/WrapPin](https://github.com/suversal/WrapPin) 的非官方分支。原版最低需要 iOS 18；這個分支**加回 iOS 17.4 以上的支援**，並做了一些介面改善。iOS 18 以上的裝置也能裝，不過建議直接用上游版本。

> 已在 iPhone XS Max（iOS 17.6）上實測：固定定位、步行模擬和鎖定畫面的即時動態都能正常使用。

## 與上游的差異

| 項目 | 上游 WrapPin | 這個分支 |
| --- | --- | --- |
| 最低系統 | iOS 18.0 | **iOS 17.4** |
| 配對檔 | RPPairing（`.rppairing`） | iOS 17 用 **Lockdown 配對檔**（`.mobiledevicepairing` / `pairingFile.plist`）；iOS 18 以上照舊用 RPPairing |
| 連線方式 | 遠端配對 + TCP 隧道 | iOS 17 改用 lockdown 的 **CoreDeviceProxy** 隧道 |
| 開發者映像（DDI） | 不處理 | iOS 17 會**自動下載並掛載**，重開機後也會自動重新掛載 |
| 放置圖釘 | 輕點地圖 | **長按地圖**（約 0.4 秒，會震動回饋），避免拖動或誤觸時跑掉 |
| 鎖定畫面 / 靈動島 | 無 | **即時動態（Live Activity）**：地點、已持續時間；步行或開車時有**進度條**和預計剩餘時間 |
| 範圍偏移 | 無 | **框一個範圍讓定位在裡面移動**：漫遊／跳點／微飄三種方式，速度、間隔、半徑可調，範圍可以存起來重複使用 |
| 座標模式 | 每個地點在卡片上切換 | 移到**設定**裡統一調整（自動／WGS84／GCJ-02），定位卡片更簡潔 |
| 介面 | — | 底部卡片外框固定、只捲動內容；展開或收合詳情、按鈕狀態、收藏、複製等互動都加了動畫；兩個主要按鈕一樣大 |
| 地圖流暢度 | — | 修正雙指縮放卡頓 |
| 更新提醒 | 檢查上游 Release | 檢查**這個分支**的 Release |

## 需要準備

- iPhone，系統 **iOS 17.4 以上**（設定 → 一般 → 關於本機）
- 一台電腦（Windows、Mac 或 Linux），只有第一次安裝和產生配對檔時需要
- [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)（App Store，需要非中國區帳號）
- [SideStore](https://sidestore.io)，用 [iLoader](https://iloader.app/) 從電腦安裝（[SideStore 安裝說明](https://docs.sidestore.io/docs/installation/prerequisites)）
- [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases/latest)，用來產生配對檔

## 安裝步驟

1. **安裝 LocalDevVPN**，打開並連線一次
2. **用 iLoader 安裝 SideStore**：手機用 USB 接上電腦，照 iLoader 的指示安裝。裝好後到「設定 → 一般 → VPN 與裝置管理」信任開發者
3. **開啟開發者模式**：設定 → 隱私權與安全性 → 開發者模式，開啟後手機會重新開機
4. **產生配對檔**：在電腦打開 idevice_pair，選這台 iPhone，產生 **Lockdown** 配對檔（**不是** RPPairing），存成 `.mobiledevicepairing` 或 `pairingFile.plist`。你給 SideStore 用的那份配對檔也可以直接拿來用
5. **把配對檔傳到手機**，存進「檔案」App
6. **下載 IPA**：到 [Releases](https://github.com/shuili1013/WrapPin-os17/releases/latest) 下載最新的 `WrapPin-Standard-…-unsigned.ipa`，存進「檔案」App
7. **用 SideStore 安裝**：打開 SideStore → 加號 → 從「檔案」選擇 IPA（不要用網址安裝）

> 這版內含即時動態的 Widget 擴充，SideStore 安裝時會多註冊一個 App ID。免費 Apple ID 每 7 天最多 10 個 App ID，不夠時請先移除其他側載 App。

## 第一次設定

1. 打開 WrapPin → **Device Setup（裝置連接）**
2. 按 **Import Pairing File**，選擇剛剛的配對檔
3. 往下滑到 **Developer Disk Image**，按 **Download Developer Disk Image**，下載約 17 MB，只需要下載一次
4. 按右上角 **Done**

## 使用方式

**固定定位**
1. 打開 LocalDevVPN 並連線
2. 回到 WrapPin，**長按地圖**放置圖釘，或在上方搜尋地點、輸入座標
3. 按 **Start Location**。第一次連線（以及每次重開機後第一次）會先掛載開發者映像，要等 10–60 秒
4. 狀態變成 **Session active** 就成功了，鎖定畫面會出現即時動態
5. 想換位置：長按另一個地點 → 按 **Update Location**
6. 結束：按 **Stop & Restore**，會恢復真實定位

**步行 / 開車模擬**
1. 選好目的地後按 **Preview Walk** 或 **Preview Drive**
2. 有多條路線時，點地圖上的路線或卡片上的選項切換
3. 按開始後，鎖定畫面的即時動態會顯示進度條、百分比和預計剩餘時間；暫停時會顯示「已暫停」

**範圍偏移**
1. 在定位卡片按 **Area Drift（範圍偏移）**，地圖上會出現一個紫色虛線框
2. **拖四個角**調整大小、**拖中間的圓點**移動位置。按 ⌖ 按鈕可以讓框符合目前的地圖畫面
3. 選擇偏移方式：
   - **漫遊**：用走路的方式走到框內隨機地點，偶爾停留一下。可調**速度**（1–30 km/h）和**最長停留**時間（0–120 秒）
   - **跳點**：每隔固定時間直接跳到框內隨機位置，可調**間隔**（3–300 秒）
   - **微飄**：在框中心附近輕微晃動，像 GPS 誤差，可調**半徑**（2–50 公尺）
4. 按 **Start Drifting（開始偏移）**。進行中也能直接改方式和數值，會立刻套用
5. **暫停**：先停住不動；**停在這裡**：結束偏移，定位留在目前位置；**Stop & Restore**：結束並恢復真實定位
6. **儲存範圍**：按 Save Area 取名字存起來，之後從 **Saved Areas（已存範圍）** 直接選用。在列表裡左滑可以刪除，長按可以改名

> 範圍偏移要靠 WrapPin 持續送出位置，**把 WrapPin 滑掉後會停在最後的位置**。

**座標模式**
到 **設定 → 定位 → 座標模式** 調整：
- **自動**（預設）：在中國大陸用 GCJ-02，其他地方（包括台灣）用 WGS84
- **WGS84** / **GCJ-02**：固定使用其中一種

在台灣用「自動」或「WGS84」都可以。定位跟地圖有偏差時再切換另一種，固定定位進行中修改會立刻生效。

## 常見問題

- **匯入時說需要 Lockdown 配對檔**：你匯入的是 RPPairing。請用 idevice_pair 改選 Lockdown 重新產生
- **一直卡在連線**：確認 LocalDevVPN 已連線、開發者模式有開、手機連著 Wi‑Fi。App 提示關閉行動網路時，先照著做，連上後再打開
- **提示開發者映像未掛載**：到 Device Setup 重新下載開發者映像，並確認手機能上網（掛載時要向 Apple 取得簽章）
- **鎖定畫面沒有即時動態**：到「設定 → WrapPin」開啟「即時動態」；定位成功時 WrapPin 要在前景，若當時在其他 App，切回 WrapPin 就會出現
- **定位卡在假位置**：打開 WrapPin 按 Stop & Restore，或直接重新開機
- **7 天後打不開**：免費帳號的簽名只有 7 天，打開 SideStore 重新整理（Refresh）即可
- **其他錯誤**：到「設定 → 連線檢測（Connection Health）」複製診斷資訊，到 [Issues](https://github.com/shuili1013/WrapPin-os17/issues) 回報，**不要**附上配對檔

## 從原始碼編譯

推送到 `ios17-lockdown` 分支後，GitHub Actions 會重新編譯 Rust 配對引擎、執行離線檢查、打包未簽名 IPA，並自動發布 Release（tag 為 `v<版本>.<build>`）。要發布新版，請先遞增 `Configuration/Version.xcconfig` 裡的 `CURRENT_PROJECT_VERSION`。

## 授權與署名

- Forked from [suversal/WrapPin](https://github.com/suversal/WrapPin)，而 WrapPin 本身是 Sean Howarth 的 [Roam Control](https://github.com/seanhowarthdev/Roam-Control) 的社群分支
- 沿用上游的 [PolyForm Noncommercial License 1.0.0](LICENSE)，僅供非商業用途；原作者與 suversal 的署名、第三方授權檔（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[NOTICE](NOTICE)）均予保留
- 這個分支與上游作者無關，問題請在[本 repo 的 Issues](https://github.com/shuili1013/WrapPin-os17/issues) 回報，不要回報到上游
