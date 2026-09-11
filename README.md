# just-a-launcher

最小 Android TV launcher：一個 GridView 列出所有 TV app（LEANBACK_LAUNCHER），沒有動畫、桌布、
推薦列、常駐服務。常駐記憶體約 35MB（Google TV 首頁 193MB、Projectivy 80MB）。

原本是給 BenQ GV01 投影機（Android TV 14、2GB RAM）做的，任何 Android TV / Google TV 都能用。

![just-a-launcher 首頁](docs/screenshot.png)

## 為什麼

測試機：BenQ GV01 投影機（MediaTek MT9632，4 核 A55 1.55GHz，2GB RAM，Android TV 14）。
停在首頁、焦點在 app 格子、遙控器不碰，每分鐘取樣一次連續 9 分鐘，數字全程沒有浮動：

| 閒置 | Google TV 首頁 | Google TV 僅限應用程式模式 | Projectivy Launcher* | just-a-launcher |
|---|---|---|---|---|
| 常駐 RAM（PSS，含副程序） | 193MB | 136MB | 80MB + 27MB zram | 35MB |
| 首頁程序 CPU（佔一核） | 48% | 40% | 2.6% | 0% |
| 畫面合成 surfaceflinger（佔一核） | 33% | 32% | ~0 | 0% |
| **全機 CPU（四核）** | **39%** | **38%** | ~15% | **10%** |
| 每秒重畫 | 61 | 61 | 0 | 0 |
| 廣告 | 有 | 頂部整頁輪播還在 | 無 | 無 |

\* Projectivy 為單次取樣，已在其設定中關掉動態桌布和聚焦動畫；預設設定下每秒重畫 60 次。

Google TV 首頁閒置時聚焦光圈每秒重畫 61 次，首頁加畫面合成佔掉 0.8 核，整台機器閒置就有四成在忙。
遙控器按鍵、影片解碼都跟它搶，這是「慢」的主因。「僅限應用程式模式」（設定 → 帳戶與登入 → 帳戶）
拿掉推薦列和預覽影片，省了 57MB，但頂部輪播廣告還在、光圈照樣重畫，CPU 幾乎沒變。

RAM 的影響是非線性的。2GB 的裝置扣掉系統後可用的只有三、四百 MB，首頁少佔 160MB，
Netflix、YouTube 就能同時留在記憶體，切換 1 秒而不是被殺掉後冷啟動 10 秒。
同樣的 160MB 在 8GB 的電視上幾乎沒感覺。

量法（`dumpsys cpuinfo` 每個程序的 % 是佔一核，只有 TOTAL 是佔全部核心）：

```
adb shell dumpsys cpuinfo | head                                    # 誰在吃 CPU
adb shell dumpsys gfxinfo <套件> | grep 'Total frames'              # 隔 60 秒量兩次取差 = 重畫次數
adb shell dumpsys meminfo <套件> | grep 'TOTAL PSS'
```

## 需求

- Android TV / Google TV，Android 5.0 以上。不符的裝置（手機、平板、太舊的電視）安裝時會直接被拒
- 一台電腦，或一支 Android 手機 / 平板（用 Termux）。電視開啟開發人員選項 → 網路偵錯
- 電腦 / 手機和電視連同一個 Wi-Fi / 區網（訪客網路通常會隔離裝置，不行）

想先確認再裝：電視「設定 → 關於 → Android 版本」5.0 以上即可。腳本也會自己檢查，不符會拒絕。

## 安裝

APK 在 [Releases](https://github.com/hungmi/just-a-launcher/releases/latest)，固定網址
`https://github.com/hungmi/just-a-launcher/releases/latest/download/just-a-launcher.apk`。

### 用腳本裝（電腦或 Android 手機）

`install.sh` 會自己找電視、連線、安裝、設為首頁。每一步先問你，直接按 Enter 就是「是」。
只做三件事：`adb install`、`set-home-activity`、Google TV 機型停用 launcherx 與 setupwraith，
不會移除系統 app、不 root。

```
curl -LO https://github.com/hungmi/just-a-launcher/releases/latest/download/install.sh && bash install.sh
```

- **電腦**（macOS / Linux）：要先有 adb 和 curl，缺的話腳本會告訴你怎麼裝。Windows 沒有 bash，走下面手動步驟
- **Android 手機 / 平板**：裝 [Termux](https://github.com/termux/termux-app/releases)（GitHub 或 F-Droid 版，
  Play 商店那個已停更），開起來貼上面那行。缺 adb 會問你要不要裝，Enter 就好，約 1–2 分鐘
- 電視會跳「允許 USB 偵錯嗎？」，用遙控器選「一律允許」。不小心按到取消，回來按 Enter 會再跳一次
- 還原：`bash install.sh --restore`

### 手動安裝（Windows，或想知道腳本做了什麼）

1. 連線
   ```
   adb connect <電視 IP>
   ```
2. 記下原本的首頁，還原要用
   ```
   adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
   ```
   會列出好幾個，看 `priority=` 數字最大的那個才是現在的首頁。Google TV 機型是
   `com.google.android.apps.tv.launcherx/.home.HomeActivity`（priority=2）；`setupwraith` 是設定精靈、
   `FallbackHome` 是系統備用，都不是。
3. 安裝、設為首頁。電視沒有「選預設首頁」的 UI，一定要用第二行那個指令
   ```
   adb install -r just-a-launcher.apk
   adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
   ```
4. 確認
   ```
   adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
   ```
   印出 `tw.hungmi.justalauncher/.MainActivity` → **完成**，按 HOME 就是新首頁，下面不用做。
   印出別的 → 繼續。Google TV 機型（BenQ GV01、小米盒子 S 2 代、Chromecast with Google TV…）
   一定會印 `com.google.android.apps.tv.launcherx/...`，set-home-activity 對它沒用。
5. 停用原本的首頁。**兩個都要停**：只停第一個，HOME 會被設定精靈（setupwraith）攔成黑畫面，
   看起來像遙控器壞了。每停一個 adb 會斷線，重連
   ```
   adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
   adb connect <電視 IP>
   adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
   adb connect <電視 IP>
   ```
6. 再跑一次第 4 步的指令，印出 `tw.hungmi.justalauncher/.MainActivity` 就完成。

做了第 5 步的副作用：之後要**新增 Google 帳號**或 Play 商店要求重新登入時，先
`adb shell pm enable --user 0 com.google.android.tungsten.setupwraith`，弄完再停用。

第 2 步列出的不是 Google TV 的話沒測過。第 4 步不過就把第 5 步的套件換成第 2 步列出的那個。

## 讓 AI agent 幫你裝

想讓 Claude Code 之類能跑終端機的 agent 代勞，貼給它：

```
幫我執行 curl -LO https://github.com/hungmi/just-a-launcher/releases/latest/download/install.sh && bash install.sh
每一步用白話解釋你在做什麼，腳本問的問題先問我再回答。
```

## 還原 / 切回原本的首頁

用腳本裝的：

```
bash install.sh --restore
```

會啟用兩個套件、設回安裝時記下的首頁、移除 just-a-launcher。手動裝的照下面做：

```
adb shell cmd package set-home-activity --user 0 <原本的 launcher>/<activity>
```

原本的 launcher 用這個查：`adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME`。

安裝時有做第 5 步（停用兩個套件）的話，先開回來再設：

```
adb shell pm enable --user 0 com.google.android.apps.tv.launcherx
adb connect <電視 IP>
adb shell pm enable --user 0 com.google.android.tungsten.setupwraith
adb connect <電視 IP>
adb shell cmd package set-home-activity --user 0 com.google.android.apps.tv.launcherx/.home.HomeActivity
```

**沒有 adb 能做的**：設定 → 應用程式 → 查看所有應用程式 → 顯示系統應用程式 → 原本的首頁 app →
「啟用」/「開啟」，可以把它當一般 app 打開。**沒有 adb 不能做的**：把它設回 HOME 鍵的預設首頁，
Android TV 沒有這個介面。移除 just-a-launcher 也一樣：先用 adb 照上面還原首頁，再 `adb uninstall tw.hungmi.justalauncher`，否則按 HOME 會黑畫面。

## 操作

D-pad 移動、OK 開 app、HOME 回首頁。「設定」用系統設定 app 那格（齒輪）。

最後一格（HDMI 插頭圖示）打開 Google TV 內建的輸入端選單（HDMI 1 / HDMI 2 / …），跟遙控器的訊號源鍵是同一個畫面。
裝置沒有這個內建選單（`com.google.android.tv.inputplayer`）就不會出現這格。

這格故意不放文字：測試機上畫面只要出現任何一個字，字型檔、排版程式庫、字元貼圖快取就要多 8MB。
整個首頁零文字是 35MB 的前提。

app 列表、其他 launcher（Projectivy 等）裡不會有 just-a-launcher 這格，設定裡它歸在「系統應用程式」。
這是刻意的：它沒有 app 入口，才不會在自己的首頁裡多一格自己。切換首頁只能用 adb，見「安裝」。

沒有其他功能，也不打算加。

## 自己編（fork 才需要）

GitHub Actions（`.github/workflows/build.yml`）：push 到 main 就編出 artifact，推 `v*` tag 會建 Release
並附上 `just-a-launcher.apk`。需要在 repo secrets 放自己的簽名金鑰：`KEYSTORE_B64`（PKCS12 檔 base64）、
`KEYSTORE_PASSWORD`，alias `just-a-launcher`。沒有 Android SDK 的機器也能用這條路編。
