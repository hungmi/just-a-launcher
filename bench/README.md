# 首頁閒置效能量測

README「為什麼」那張表的量法和腳本。全部走 adb，不用 root。

## 一組的流程

一組量一個首頁，約 7 分鐘：

1. `prep`：重啟首頁程序 → HOME → `am kill-all` 清背景 app → 按導覽鍵把焦點移到 app 格子 → 截圖
2. 看截圖確認焦點位置
3. `run`：等 45 秒 → 連量 5 個 60 秒視窗 → 量完才做 gfxinfo、meminfo 這些重的 dump
4. `analyze.py`：算平均；多組一起給會印出 README 的表格

```
export TV=<電視 IP>:<port>     # adb devices 列出的名字
adb connect $TV
bench/measure.sh prep jal tw.hungmi.justalauncher     # 看 bench/runs/jal/prep.png
bench/measure.sh run jal
python3 bench/analyze.py bench/runs/gtv bench/runs/gtv_apps bench/runs/proj bench/runs/jal
```

「網路偵錯」的 port 通常是 5555；「無線偵錯」的 port 每次開關都會變，以電視上顯示的為準。

量測中別碰遙控器。螢幕逾時（測試機是 10 分鐘）一到就會進螢保，run 開始前會讀裝置的設定，
剩下的時間不夠就停下來，要你重跑 prep。analyze 發現有人按鍵或進過螢保會標 ⚠。結果在 `bench/runs/`（不進 git）。

## 各首頁

| 首頁 | 套件 | prep 的導覽鍵（HOME 之後） |
|---|---|---|
| just-a-launcher | `tw.hungmi.justalauncher` | 不用 |
| Projectivy | `com.spocky.projengmenu` | `KEYCODE_DPAD_DOWN` |
| Google TV 一般模式 | `com.google.android.apps.tv.launcherx` | `KEYCODE_DPAD_DOWN` ×3 |
| Google TV 僅限應用程式模式 | `com.google.android.apps.tv.launcherx` | `KEYCODE_DPAD_DOWN` ×2 |

導覽鍵是測試機上的次數，版面會隨版本、語言、裝了哪些 app 變，別台照 prep 的截圖調。
設定要跟上次一樣才能比：Google TV 帳戶「自動播放影片」關、Projectivy 關動態桌布和聚焦動畫。

## 切換首頁

launcherx 啟用時 `set-home-activity` 無效，所以照這個順序量：just-a-launcher → Projectivy → Google TV → 還原。
`pm enable` / `disable-user` 之後 adb 斷線就 `adb connect $TV`。下面的 activity 名稱是測試機上的版本，
別台先查：`adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME`。

```
# Projectivy
adb shell pm enable --user 0 com.spocky.projengmenu
adb shell cmd package set-home-activity --user 0 com.spocky.projengmenu/.ui.home.MainActivity

# Google TV
adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
adb shell pm disable-user --user 0 com.spocky.projengmenu
adb shell pm enable --user 0 com.google.android.apps.tv.launcherx
adb shell pm enable --user 0 com.google.android.tungsten.setupwraith
adb shell cmd package set-home-activity --user 0 com.google.android.apps.tv.launcherx/.home.HomeActivity

# 還原（跟 install.sh 同順序）
adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
adb shell cmd package set-home-activity --user 0 tw.hungmi.justalauncher/.MainActivity
```

Google TV 剛啟用會先同步內容，讓它跑 3 分鐘再 prep。

僅限應用程式模式在「設定 → 帳戶和設定檔 → 帳戶 → 最下面」。用 adb 按的話先 `am start -a android.settings.SETTINGS`；
測試機上是 下 ×4、OK、OK、下 ×8 焦點就在開關上，開啟要按兩次 OK（第二次是確認「開啟」），關閉按一次。
選單項目數量每台不同，**每步都 `bench/measure.sh shot <名字>` 截圖確認**：開關下一格是「移除設定檔」。量完關回來。

## 算法

- 首頁程序 CPU：`/proc/<pid>/stat` 的 utime + stime 差 ÷ 秒數 ÷ 100，佔一核；含 `<套件>:xxx` 副程序
- 全機 CPU：`/proc/stat` 第一行，1 − (idle + iowait) 的差 ÷ 全部欄位的差，佔全部核心
- 每秒重畫：gfxinfo 的 `Total frames rendered` 差 ÷ gfxinfo 自己的 `Uptime` 差
- 記憶體：`dumpsys meminfo --package` 每個程序的 `TOTAL PSS` 加總，已含 swap

## 踩過的坑

- `dumpsys cpuinfo` 每 5 分鐘才更新，連查拿到同一組舊數字（舊 README 寫「數字全程沒有浮動」就是這樣來的），
  還會把按遙控器那幾秒算進去
- 每秒重畫要除實際間隔：除 60 秒會算出 61，超過 60Hz 螢幕的上限
- `dumpsys meminfo <套件>` 只算主程序，Google TV 的 `:coreservices`（24–38MB）會漏掉
- gfxinfo 0 幀不等於閒置：Projectivy 0 幀，但主執行緒每秒被叫醒 80 次，吃掉 6% CPU。
  要查就看 `/proc/<pid>/task/*/status` 的 `voluntary_ctxt_switches`，隔 10 秒量兩次
- Google TV 首頁的記憶體會在 140–190MB 之間跳（輪播大圖解碼後放在 Native Heap）；
  同一個程序從一般模式切到僅限應用程式模式，舊快取還在。所以 prep 每次都先 force-stop
- 首頁叫起來的其他 app 不算在它的套件名下：量 Google TV 首頁時 HBO Max 在跑（60MB）。
  多組 analyze 的「各程序對照」會列出來，要不要算進首頁成本自己判斷
- load average 沒意義：這台約 45 個驅動 kernel thread 永遠卡在 D state，閒置也是 55–60
- Wi-Fi 上 adb pull 大檔會卡在 1MiB → 腳本會逾時重連
- 這台 `screencap` 會先在 stdout 印一行 `Init wrapper sys mutex successful`，`exec-out screencap` 拿到的 PNG 是壞的

## 2026-09-24 結果

BenQ GV01（`BenQ/BenQ_GV01/himalaya:14/UKNV.260626.001/15736158`），4 核 Cortex-A53（CPU part 0xd03），
1920×1080 60Hz。launcherx 1.0.971258372、Projectivy 4.71、just-a-launcher 0.8。

| | Google TV 一般模式 | 僅限應用程式模式 | Projectivy | just-a-launcher |
|---|---|---|---|---|
| 記憶體 | 183MB | 190MB（從一般模式切過去 175MB） | 78MB | 39MB（跑了 7 小時：38MB） |
| 首頁程序 CPU（佔一核） | 43.3% | 38.8% | 6.1% | 0.0% |
| surfaceflinger（佔一核） | 32.3% | 31.7% | 1.7% | 0.0% |
| composer HAL（佔一核） | 7.7% | 7.5% | 0.8% | 0.8% |
| 全機（四核） | 36.8% | 33.9% | 12.7% | 11.8% |
| 每秒重畫 | 59.9 | 59.9 | 0 | 0 |

焦點位置：一般模式焦點在哪都是 60；僅限應用程式模式焦點在 app 格子 60、在頂部輪播 5.7。
