# just-a-launcher

最小 Android TV launcher：一個 GridView 列出所有 TV app（LEANBACK_LAUNCHER），沒有動畫、桌布、
推薦列、常駐服務。常駐記憶體約 30MB（Google TV 首頁 200MB+、Projectivy 80MB）。

原本是給 BenQ GV01 投影機（Android TV 14、2GB RAM）做的，任何 Android TV / Google TV 都能用。

![just-a-launcher 首頁](docs/screenshot.png)

## 為什麼

在 BenQ GV01（MediaTek MT9632，4 核 A55 1.55GHz，2GB RAM）上量的。投影機停在首頁、焦點在 app 格子、
**遙控器不碰**，每分鐘取樣一次連續 9 分鐘，數字全程沒有浮動：

| 閒置 | Google TV 首頁 | Google TV 僅限應用程式模式 | Projectivy Launcher* | just-a-launcher |
|---|---|---|---|---|
| 常駐 RAM（PSS，含副程序） | 193MB | 136MB | 80MB + 27MB zram | 35MB |
| 首頁程序 CPU（佔一核） | 48% | 40% | 2.6% | 0% |
| 畫面合成 surfaceflinger（佔一核） | 33% | 32% | ~0 | 0% |
| **全機 CPU（四核）** | **39%** | **38%** | ~15% | **10%** |
| 每秒重畫 | 61 | 61 | 0 | 0 |
| 廣告 | 有 | 頂部整頁輪播還在 | 無 | 無 |

\* Projectivy 是前一天單次取樣，已關掉動態桌布和聚焦動畫；預設設定下每秒重畫 60 次。

Google TV 首頁閒置時聚焦光圈每秒重畫 61 次，首頁加畫面合成佔掉 0.8 核，整台機器閒置就有四成在忙。
遙控器按鍵、影片解碼都跟它搶，這是「慢」的主因。「僅限應用程式模式」（設定 → 帳戶與登入 → 帳戶）
拿掉推薦列和預覽影片，省了 57MB，但頂部輪播廣告還在、光圈照樣重畫，CPU 幾乎沒變。

RAM 的影響是非線性的：可用記憶體從 73MB 變 625MB 後，Netflix、YouTube 可以同時留在記憶體，
切換 1 秒而不是被殺掉後冷啟動 10 秒。同樣的 160MB 在 8GB 的電視上幾乎沒感覉，
在 2GB 的裝置上是「每開一個 app 就殺一個」和「常用的都留著」的差別。

量法（`dumpsys cpuinfo` 每個程序的 % 是佔一核，只有 TOTAL 是佔全部核心）：

```
adb shell dumpsys cpuinfo | head                                    # 誰在吃 CPU
adb shell dumpsys gfxinfo <套件> | grep 'Total frames'              # 隔 60 秒量兩次取差 = 重畫次數
adb shell dumpsys meminfo <套件> | grep 'TOTAL PSS'
```

## 需求

- Android TV / Google TV，Android 5.0 以上。不符的裝置（手機、平板、太舊的電視）安裝時會直接被拒
- 電腦上有 adb，電視開啟開發人員選項 → USB / 網路偵錯
- 電腦和電視連同一個 Wi-Fi / 區網（訪客網路通常會隔離裝置，不行）

想先確認再裝：電視「設定 → 關於 → Android 版本」5.0 以上即可。或用 adb：

```
adb shell getprop ro.build.version.sdk      # ≥ 21
adb shell pm list features | grep leanback  # 有輸出才是 Android TV
```

## 安裝

APK 在 [Releases](https://github.com/hungmi/just-a-launcher/releases/latest)，固定網址
`https://github.com/hungmi/just-a-launcher/releases/latest/download/just-a-launcher.apk`。

```
adb connect <電視 IP>
adb install -r just-a-launcher.apk
adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
```

按 HOME 鍵就是新首頁。電視沒有「選預設首頁」的 UI，一定要用第三行那個指令。

## 讓 AI agent 幫你裝

不想自己打指令，把下面整段貼給 Claude Code 之類能跑終端機的 agent。
它會自己找電視 IP：找得到一台就直接用，找到多台或找不到才問你。

<details>
<summary>中文 prompt</summary>

```
請幫我把 just-a-launcher（https://github.com/hungmi/just-a-launcher）裝到我的 Android TV 並設為首頁。
指令你自己執行，每一步用白話說明你在做什麼。

規則
1. 只能用 adb install 和 cmd package set-home-activity。不要 pm uninstall、不要 pm disable
   任何東西、不要 root。
2. 先確認 adb 已安裝，沒有就依我的作業系統裝：macOS `brew install android-platform-tools`、
   Debian/Ubuntu `apt install adb`、Arch `pacman -S android-tools`、Windows 下載 Google platform-tools。
3. 找電視 IP，照這個順序。確定就直接用，不確定就列選項問我：
   前提：電腦和電視要在同一個 Wi-Fi / 區網，先提醒我確認（訪客網路會隔離裝置）。
   a. `adb devices` 已經有裝置 → 直接用。
   b. 掃區網哪台開著 5555 port（Android TV 的網路偵錯）。Linux/macOS 範例：
        net=$(ip -4 route get 1 | awk '{print $7}' | cut -d. -f1-3)   # macOS：ipconfig getifaddr en0
        for i in $(seq 1 254); do (timeout 0.3 bash -c "</dev/tcp/$net.$i/5555" 2>/dev/null && echo $net.$i) & done; wait
      只找到一台 → 就是它。
   c. 沒有或多台 → 用 mDNS 列出區網的 Android TV：
        Linux `avahi-browse -rtp _androidtvremote2._tcp`、macOS `dns-sd -B _androidtvremote2._tcp local.`
      把裝置名稱和 IP 列給我選。找不到 5555 的話，提醒我在那台電視開啟：
      設定 → 系統 → 關於 → 版本號連按 7 下 → 開發人員選項 → 網路偵錯（或 USB 偵錯）。
   d. 都找不到 → 請我到電視「設定 → 網路 → 狀態」看 IP。
4. 安裝：
        adb connect <IP>:5555        # 電視會跳「允許偵錯？」，提醒我在電視按允許
        curl -LO https://github.com/hungmi/just-a-launcher/releases/latest/download/just-a-launcher.apk
        adb install -r just-a-launcher.apk
   若出現 INSTALL_FAILED_OLDER_SDK 或 INSTALL_FAILED_MISSING_FEATURE，代表這台不支援，
   停下來告訴我，不要想辦法繞過。
5. 設首頁前先記下原本的首頁，之後還原用：
        adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
   然後：
        adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
        adb shell input keyevent KEYCODE_HOME
6. 請我看電視：應該是黑底、一格一格的 app。請我用遙控器試 D-pad 移動、OK 開一個 app、HOME 回來。
7. 最後給我一行還原指令：
        adb shell cmd package set-home-activity --user 0 <第 5 步記下的原本 launcher>
```

</details>

<details>
<summary>English prompt</summary>

```
Install just-a-launcher (https://github.com/hungmi/just-a-launcher) on my Android TV and make it the home screen.
Run the commands yourself and explain each step in plain language.

Rules
1. Only `adb install` and `cmd package set-home-activity`. No `pm uninstall`, no `pm disable`,
   no rooting.
2. Check that adb is installed; if not, install it for my OS: macOS `brew install android-platform-tools`,
   Debian/Ubuntu `apt install adb`, Arch `pacman -S android-tools`, Windows: download Google platform-tools.
3. Find the TV's IP in this order. If it is unambiguous, use it; otherwise list the options and ask me:
   First remind me that the computer and the TV must be on the same Wi-Fi / LAN (guest networks isolate devices).
   a. `adb devices` already shows a device -> use it.
   b. Scan the LAN for hosts with port 5555 open (Android TV network debugging). Linux/macOS example:
        net=$(ip -4 route get 1 | awk '{print $7}' | cut -d. -f1-3)   # macOS: ipconfig getifaddr en0
        for i in $(seq 1 254); do (timeout 0.3 bash -c "</dev/tcp/$net.$i/5555" 2>/dev/null && echo $net.$i) & done; wait
      Exactly one hit -> that is the TV.
   c. None or several -> list Android TVs on the LAN via mDNS:
        Linux `avahi-browse -rtp _androidtvremote2._tcp`, macOS `dns-sd -B _androidtvremote2._tcp local.`
      Show me the device names and IPs to choose from. If nothing had 5555 open, remind me to enable on the TV:
      Settings -> System -> About -> tap Build number 7 times -> Developer options -> Network debugging (or USB debugging).
   d. Still nothing -> ask me to read the IP from the TV: Settings -> Network -> Status.
4. Install:
        adb connect <IP>:5555        # the TV shows "Allow debugging?" - tell me to accept it on the TV
        curl -LO https://github.com/hungmi/just-a-launcher/releases/latest/download/just-a-launcher.apk
        adb install -r just-a-launcher.apk
   If you see INSTALL_FAILED_OLDER_SDK or INSTALL_FAILED_MISSING_FEATURE the device is not supported.
   Stop and tell me; do not try to work around it.
5. Before changing the home screen, record the current one so it can be restored:
        adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
   Then:
        adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
        adb shell input keyevent KEYCODE_HOME
6. Ask me to look at the TV: a black screen with a grid of app tiles. Have me test D-pad movement,
   OK to open an app, HOME to come back.
7. Finish with the one-line undo command:
        adb shell cmd package set-home-activity --user 0 <the original launcher from step 5>
```

</details>

## 還原 / 切回原本的首頁

```
adb shell cmd package set-home-activity --user 0 <原本的 launcher>/<activity>
```

原本的 launcher 用這個查：`adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME`。
Google TV 是 `com.google.android.apps.tv.launcherx/.home.HomeActivity`（若被停用要先 `pm enable --user 0`）。

**沒有 adb 能做的**：設定 → 應用程式 → 查看所有應用程式 → 顯示系統應用程式 → 原本的首頁 app →
「啟用」/「開啟」，可以把它當一般 app 打開。**沒有 adb 不能做的**：把它設回 HOME 鍵的預設首頁，
Android TV 沒有這個介面。移除 just-a-launcher 也一樣：先用 adb 把首頁設回去，再移除，否則按 HOME 會黑畫面。

## 操作

D-pad 移動、OK 開 app、HOME 回首頁。「設定」用系統設定 app 那格（齒輪）。

最後一格「訊號源」打開 Google TV 內建的輸入端選單（HDMI 1 / HDMI 2 / …），跟遙控器的訊號源鍵是同一個畫面。
裝置沒有這個內建選單（`com.google.android.tv.inputplayer`）就不會出現這格。

沒有其他功能，也不打算加。

## 編譯

GitHub Actions（`.github/workflows/build.yml`）：push 到 main 就編，artifact `just-a-launcher.apk`；
推 `v*` tag 會建 Release 並附上 `just-a-launcher.apk`。
簽名金鑰放 secrets `KEYSTORE_B64`（PKCS12 base64）、`KEYSTORE_PASSWORD`，alias `just-a-launcher`。
