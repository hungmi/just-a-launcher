#!/usr/bin/env bash
# 首頁閒置效能量測（主機端）。流程、各首頁的導覽鍵、注意事項見 bench/README.md。
#
#   measure.sh prep LABEL PKG [KEY...]   重啟首頁 PKG → HOME → 清背景 app → 按導覽鍵 → 截圖
#   measure.sh run  LABEL [N]            等 SETTLE 秒 → N 個 60 秒視窗（預設 5）→ gfxinfo、meminfo
#   measure.sh shot NAME                 截圖到 bench/runs/NAME.png，手動導覽時確認畫面用
#
# 裝置用環境變數 TV 指定，就是 adb devices 列出的那個名字，例如 TV=<電視 IP>:5555。
# 「無線偵錯」的 port 每次開關都會變，以電視上顯示的為準。結果在 bench/runs/LABEL/，再用 analyze.py 看。
set -u
TV=${TV:?用 TV=<電視 IP>:<port> 指定裝置（adb devices 列出的名字）}
SETTLE=${SETTLE:-45}
HERE=$(cd "$(dirname "$0")" && pwd)
A=(adb -s "$TV")
MODE=${1:?用法見檔頭}; NAME=${2:?用法見檔頭}; shift 2
OUT=$HERE/runs/$NAME

log() { mkdir -p "$OUT"; echo "[$(date +%T)] $*" | tee -a "$OUT/log.txt"; }
reconnect() { adb disconnect "$TV" >/dev/null 2>&1; sleep 1; timeout 15 adb connect "$TV" </dev/null >/dev/null 2>&1; sleep 2; }
# Wi-Fi 上的 adb 偶爾整條卡住（pull 大檔會停在 1MiB）：逾時就重連再試。
# 遠端指令後面補 true，非 0 就一定是 adb 本身出錯，grep 沒找到之類的不會被當成斷線
sh_() { local i; for i in 1 2 3; do timeout 90 "${A[@]}" shell "$*; true" </dev/null && return 0; log "adb 逾時或斷線，重連（第 $i 次）"; reconnect; done; return 1; }
pull_() { local i; for i in 1 2 3; do timeout 90 "${A[@]}" pull "$1" "$2" </dev/null >/dev/null 2>&1 && return 0; log "adb pull 逾時，重連（第 $i 次）"; reconnect; done; return 1; }
# BenQ GV01 的 screencap 會先在 stdout 印一行字，所以寫成檔案再 pull
shot() { sh_ "screencap -p /data/local/tmp/s.png" >/dev/null; pull_ /data/local/tmp/s.png "$1"; sh_ "rm /data/local/tmp/s.png"; }
# 欄位名稱各版本不同（Android 14 是 lastUserActivityTime，舊版是 mLastUserActivityTime）
power() { sh_ "dumpsys power | grep -iE 'mWakefulness=|lastUserActivityTime='; dumpsys dreams | grep -m1 mCurrentDream"; }
gfx() { sh_ "dumpsys gfxinfo $PKG | grep -E '^Uptime|^\*\*|Total frames rendered'"; }
timeout_s() { local t; t=$(sh_ "settings get system screen_off_timeout" | tr -dc 0-9); [ -n "$t" ] && echo $((t / 1000)); }
# 螢幕逾時（每台設定不同）扣掉距離上次按鍵的時間 = 還剩幾秒會進螢保或關螢幕
budget() {
  local t ago
  t=$(timeout_s); ago=$(sh_ "dumpsys power | grep -iE 'lastUserActivityTime='" | grep -oE '[0-9]+ ms ago' | head -1 | tr -dc 0-9)
  [ -n "$t" ] && [ -n "$ago" ] && echo $((t - ago / 1000))
}

case $MODE in
shot)
  mkdir -p "$HERE/runs"; shot "$HERE/runs/$NAME.png"; echo "$HERE/runs/$NAME.png" ;;

prep)
  PKG=${1:?要給首頁的套件名}; shift
  mkdir -p "$OUT"; echo "$PKG" > "$OUT/pkg"
  # 每組都用剛啟動的程序：同一個程序切過模式會留著舊快取，記憶體沒法比
  sh_ "am force-stop $PKG; input keyevent KEYCODE_HOME" >/dev/null
  for _ in $(seq 30); do [ -n "$(sh_ "pidof $PKG")" ] && break; sleep 1; done
  sleep 5
  sh_ "am kill-all"; sleep 2
  for k in "$@"; do sh_ "input keyevent $k"; sleep 1.5; done
  sleep 3; shot "$OUT/prep.png"
  log "prep 完成，看 $OUT/prep.png 確認焦點。這台螢幕逾時 $(timeout_s) 秒，run 開始時會檢查時間夠不夠" ;;

run)
  N=${1:-5}; PKG=$(cat "$OUT/pkg")
  need=$((SETTLE + N * 60 + 30)); left=$(budget)
  if [ -n "$left" ] && [ "$need" -gt "$left" ]; then
    log "再 ${left} 秒螢幕就逾時，這組要 ${need} 秒：重跑 prep，或把 N 調小"; exit 1
  fi
  log "等 ${SETTLE} 秒"; sleep "$SETTLE"
  power > "$OUT/power_before.txt"
  gfx > "$OUT/gfxA.txt"
  timeout 60 "${A[@]}" push "$HERE/snap.sh" /data/local/tmp/snap.sh </dev/null >/dev/null 2>&1 \
    || { reconnect; "${A[@]}" push "$HERE/snap.sh" /data/local/tmp/snap.sh </dev/null >/dev/null 2>&1; }
  # 不經 sh_ 重試：第一次其實跑起來了卻逾時的話，重試會有兩支同時寫 snap.out
  timeout 30 "${A[@]}" shell "setsid sh /data/local/tmp/snap.sh /data/local/tmp/snap.out $N 60 >/dev/null 2>&1 </dev/null &" </dev/null \
    || { log "裝置端沒跑起來，重跑 run"; exit 1; }
  log "開始 $N 個 60 秒視窗，別碰遙控器"
  sleep $((N * 60 + 8))
  for _ in $(seq 40); do sh_ "tail -n1 /data/local/tmp/snap.out" | grep -q DONE && break; sleep 3; done
  gfx > "$OUT/gfxB.txt"
  power > "$OUT/power_after.txt"
  shot "$OUT/after.png"
  # 重的 dump 放在視窗之後
  sh_ "dumpsys meminfo --package $PKG" > "$OUT/meminfo_pkg.txt"
  sh_ "cat /proc/meminfo" > "$OUT/proc_meminfo.txt"
  sh_ "dumpsys meminfo" > "$OUT/meminfo_all.txt"
  pull_ /data/local/tmp/snap.out "$OUT/snap.out"
  sh_ "rm /data/local/tmp/snap.out /data/local/tmp/snap.sh"
  log "完成：python3 $HERE/analyze.py $OUT" ;;

*) echo "不認得的模式：$MODE（prep / run / shot）"; exit 1 ;;
esac
