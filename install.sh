#!/usr/bin/env bash
# just-a-launcher 安裝 / 還原腳本。可在 Termux（Android 手機）、macOS、Linux 執行。
#
#   bash install.sh            安裝並設為首頁
#   bash install.sh --restore  還原原本首頁並移除
#
# 每一步都會先問，直接按 Enter 就是「是」。
# 只會做這幾件事：adb install、set-home-activity，以及（Google TV 機型）停用
# launcherx 與 setupwraith 兩個套件。不會 uninstall 系統 app、不會 root。

set -u

REPO=https://github.com/hungmi/just-a-launcher
APK_URL=$REPO/releases/latest/download/just-a-launcher.apk
PKG=tw.hungmi.justalauncher
HOME_ACT=$PKG/.MainActivity
LAUNCHERX=com.google.android.apps.tv.launcherx
SETUPWRAITH=com.google.android.tungsten.setupwraith
STATE=$HOME/.just-a-launcher-original-home
HOME_QUERY=(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME)

SERIAL=

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die()  { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ask "問題" → 回傳 0 = 是；Enter 預設是
# 有終端機就從 /dev/tty 讀（curl | bash 也能用），沒有就讀 stdin
readline() {
  REPLY=
  printf '\033[33m▶ %s\033[0m' "$1"
  { read -r REPLY </dev/tty; } 2>/dev/null && return
  read -r REPLY || die "沒有輸入（stdin 已結束），中止。"
}
ask() {
  readline "$1 [Y/n]（直接按 Enter = 是）"
  case "$REPLY" in n|N|no|NO) return 1;; *) return 0;; esac
}
# prompt "提示" → 印出使用者輸入
prompt() { readline "$1"; printf '%s' "$REPLY"; }
step() { ask "$1" || die "已取消。"; }

# </dev/null：adb shell 會把 stdin 轉給遠端，否則會吃掉使用者的回答
sh_tv()  { adb -s "$SERIAL" shell "$@" </dev/null | tr -d '\r'; }
current_home() { sh_tv "${HOME_QUERY[@]}" | tail -n 1; }

# ---------- 前置檢查 ----------
is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]; }
check_tools() {
  local missing=()
  for c in adb curl; do command -v "$c" >/dev/null || missing+=("$c"); done
  # Termux 內建 curl 可能跟後來裝的套件版本對不上（CANNOT LINK EXECUTABLE），一起當缺少
  curl --version >/dev/null 2>&1 || case " ${missing[*]:-} " in *" curl "*) ;; *) missing+=(curl);; esac
  [ ${#missing[@]} -eq 0 ] && return
  say "缺少或壞掉：${missing[*]}"
  if is_termux; then
    step "Termux 可以直接裝：先升級全部套件（不然版本會對不上、curl 會壞），再裝 android-tools。約 1–2 分鐘，要執行嗎？"
    # 用 apt-get 不用 pkg：pkg upgrade 帶參數時會默默不升級，回傳卻是成功。
    # noninteractive + force-confnew：不然 dpkg 會停下來問 openssl.cnf 之類的設定檔要不要換
    export DEBIAN_FRONTEND=noninteractive
    apt-get -q update \
      && apt-get -q -y -o Dpkg::Options::=--force-confnew full-upgrade \
      && apt-get -q -y -o Dpkg::Options::=--force-confnew install android-tools curl || die "安裝失敗，請手動執行：pkg upgrade 然後 pkg install android-tools curl"
    for c in adb curl; do command -v "$c" >/dev/null || die "裝了但還是找不到 $c，請重開 Termux 再試。"; done
    curl --version >/dev/null 2>&1 || die "curl 還是跑不起來，請重開 Termux 再試。"
    return
  else
    note "macOS：brew install android-platform-tools   Debian/Ubuntu：sudo apt install adb curl"
    note "Arch：sudo pacman -S android-tools curl       Windows：請改用 README 手動步驟"
  fi
  exit 1
}

# ---------- 找電視 ----------
my_subnet() {
  local ip
  ip=$(ip -4 route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | head -n 1)
  [ -z "$ip" ] && command -v ipconfig >/dev/null && ip=$(ipconfig getifaddr en0 2>/dev/null)
  [ -n "$ip" ] && printf '%s' "${ip%.*}"
}
# 5555 port 有開 → 回傳 0
probe() {
  if command -v timeout >/dev/null; then
    timeout 0.4 bash -c "exec 3<>/dev/tcp/$1/5555" 2>/dev/null
  else  # macOS 沒有 timeout
    bash -c "exec 3<>/dev/tcp/$1/5555" 2>/dev/null & local pid=$!
    ( sleep 0.4; kill "$pid" 2>/dev/null ) 2>/dev/null &
    wait "$pid" 2>/dev/null
  fi
}
scan_lan() {
  local net=$1 i
  for i in $(seq 1 254); do ( probe "$net.$i" && echo "$net.$i" ) & done
  wait
}
ask_ip() {
  say "請到電視看 IP：設定 → 網路與網際網路 → 點目前連的 Wi-Fi → 「IP 位址」"
  note "手機 / 電腦要跟電視連同一個 Wi-Fi（訪客網路會隔離裝置，不行）"
  local ip
  ip=$(prompt "輸入電視 IP（例如 192.168.1.185）： ")
  [ -z "$ip" ] && die "沒有輸入 IP。"
  SERIAL=$ip:5555
}
pick_tv() {
  # 1. adb 已經連著一台
  local devs
  devs=$(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  if [ "$(printf '%s\n' "$devs" | grep -c .)" -eq 1 ]; then
    SERIAL=$devs
    say "adb 已連著一台裝置，就用它：$SERIAL"
    return
  fi

  # 2. 掃區網 5555 port
  local net
  net=$(my_subnet)
  if [ -z "$net" ]; then note "抓不到你的網段，無法自動掃描。"; ask_ip; return; fi
  say "掃區網 $net.1–254 找開著網路偵錯的電視（約 10 秒）…"
  local found n
  found=$(scan_lan "$net" | sort -t. -k4 -n)
  n=$(printf '%s\n' "$found" | grep -c .)
  if [ "$n" -eq 1 ]; then
    SERIAL=$found:5555
    say "找到一台：$found"
  elif [ "$n" -eq 0 ]; then
    say "找不到有開網路偵錯的裝置"
    note "電視：設定 → 系統 → 關於 → 「Android TV OS 版本」連按 7 下 → 回上一頁 → 開發人員選項 → 開啟「網路偵錯」（或 USB 偵錯）"
    note "如果確定已經開了，可以手動輸入 IP。"
    ask "要手動輸入 IP 嗎？" || die "開好網路偵錯後再執行一次這個腳本。"
    ask_ip
  else
    say "找到多台：$(printf '%s ' $found)"
    ask_ip
  fi
}

connect_tv() {
  case "$SERIAL" in *:*) ;; *) return;; esac   # USB 裝置不用 connect
  say "連線到 $SERIAL"
  local out state
  while :; do
    out=$(adb connect "$SERIAL" 2>&1)
    state=$(adb devices | awk -v s="$SERIAL" '$1==s{print $2}')
    case "$state" in
      device)
        if adb -s "$SERIAL" shell true >/dev/null 2>&1 </dev/null; then note "已連線"; return; fi
        note "連上了但 shell 不通，重連…"; adb disconnect "$SERIAL" >/dev/null 2>&1;;
      unauthorized)
        # 第一次連會這樣。按了取消的話同一條連線不會再問，所以先斷開，重試時才會重新跳
        note "電視畫面應該跳出「允許 USB 偵錯嗎？」，請用遙控器選「一律允許」。"
        note "沒看到或不小心按了取消：按 Enter 重試會重新跳一次。"
        adb disconnect "$SERIAL" >/dev/null 2>&1;;
      offline)
        note "裝置 offline，重連…"; adb disconnect "$SERIAL" >/dev/null 2>&1;;
      *)
        note "$out"
        note "連不上。確認電視有開網路偵錯、跟你在同一個 Wi-Fi、IP 沒打錯。";;
    esac
    ask "按 Enter 重試" || die "已取消。"
  done
}
reconnect() { case "$SERIAL" in *:*) adb connect "$SERIAL" >/dev/null 2>&1; sleep 1;; esac; }

check_tv() {
  local sdk lb model
  model=$(sh_tv getprop ro.product.model)
  sdk=$(sh_tv getprop ro.build.version.sdk)
  lb=$(sh_tv pm list features | grep -c android.software.leanback)
  say "裝置：$model（Android SDK $sdk）"
  [ "${sdk:-0}" -ge 21 ] || die "Android 版本太舊（SDK $sdk < 21），不支援。"
  [ "$lb" -ge 1 ] || die "這不是 Android TV（沒有 leanback），不支援。"
}

# ---------- 安裝 ----------
do_install() {
  local before
  before=$(current_home)
  say "目前的首頁：$before"
  if [ "$before" != "$HOME_ACT" ]; then
    printf '%s\n' "$before" > "$STATE"
    note "已記到 $STATE，還原時會用"
  fi

  step "下載並安裝 just-a-launcher？"
  local tmp; tmp=$(mktemp -d)
  curl -fL --progress-bar -o "$tmp/just-a-launcher.apk" "$APK_URL" || die "下載失敗。"
  local out
  out=$(adb -s "$SERIAL" install -r "$tmp/just-a-launcher.apk" 2>&1 </dev/null)
  rm -rf "$tmp"
  case "$out" in
    *Success*) note "安裝成功";;
    *OLDER_SDK*|*MISSING_FEATURE*) die "這台裝置不支援：$out";;
    *) die "安裝失敗：$out";;
  esac

  step "設為首頁？"
  sh_tv cmd package set-home-activity --user 0 "$HOME_ACT" >/dev/null
  local now; now=$(current_home)
  case "$now" in
    "$HOME_ACT") finish; return;;
    *"$LAUNCHERX"*) ;;
    *) say "首頁還是：$now"
       note "這台不是 Google TV，set-home-activity 沒生效，我沒測過，不自動處理。"
       note "可以試手動：adb shell pm disable-user --user 0 <上面那個套件名>，再重跑此腳本。"
       exit 1;;
  esac

  say "這是 Google TV 機型，set-home-activity 對它無效，要停用原本的首頁"
  note "會停用兩個套件：$LAUNCHERX（Google TV 首頁）和 $SETUPWRAITH（設定精靈）。"
  note "兩個都要停，只停第一個 HOME 會變黑畫面。之後要新增 Google 帳號時再暫時啟用 setupwraith（見 README）。"
  note "可用 bash install.sh --restore 全部還原。"
  step "停用這兩個套件？"
  sh_tv pm disable-user --user 0 "$LAUNCHERX"; reconnect
  sh_tv pm disable-user --user 0 "$SETUPWRAITH"; reconnect
  sh_tv cmd package set-home-activity --user 0 "$HOME_ACT" >/dev/null
  now=$(current_home)
  [ "$now" = "$HOME_ACT" ] || die "還是不行，首頁：$now。請到 $REPO/issues 貼上這段輸出。"
  finish
}
finish() {
  sh_tv input keyevent KEYCODE_HOME
  say "完成。電視現在應該是黑底、一格一格的 app。"
  note "用遙控器試：D-pad 移動、OK 開 app、HOME 回來。"
  note "要還原：bash install.sh --restore"
}

# ---------- 還原 ----------
do_restore() {
  say "還原原本的首頁並移除 just-a-launcher"
  local orig=
  [ -f "$STATE" ] && orig=$(cat "$STATE")
  [ -n "$orig" ] && note "原本的首頁：$orig"
  step "開始還原？"
  sh_tv pm enable --user 0 "$LAUNCHERX" 2>/dev/null; reconnect
  sh_tv pm enable --user 0 "$SETUPWRAITH" 2>/dev/null; reconnect
  [ -n "$orig" ] && sh_tv cmd package set-home-activity --user 0 "$orig" >/dev/null
  adb -s "$SERIAL" uninstall "$PKG" >/dev/null 2>&1 </dev/null; reconnect
  local now; now=$(current_home)
  say "現在的首頁：$now"
  case "$now" in *"$PKG"*) die "移除失敗。";; esac
  rm -f "$STATE"
  sh_tv input keyevent KEYCODE_HOME
  note "完成。"
}

# ---------- main ----------
case "${1:-}" in
  --restore) MODE=restore;;
  "")        MODE=install;;
  *) echo "用法：bash install.sh [--restore]"; exit 2;;
esac
check_tools
pick_tv
connect_tv
check_tv
if [ "$MODE" = install ]; then do_install; else do_restore; fi
