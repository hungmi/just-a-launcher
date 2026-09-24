# 裝置端（measure.sh 會推上去跑）：每 I 秒快照一次 /proc，共 N 個視窗（N+1 個快照）。
# 量測期間裝置上只有這支在動，主機不送 adb 指令。
# 用法：sh snap.sh OUT N I
OUT=$1; N=$2; I=$3
# 程序全名（/proc/<pid>/stat 的名字只有 15 字元）；前後各讀一次，放在視窗外
names() { for p in /proc/[0-9]*; do echo "N ${p#/proc/} $(tr '\0' ' ' < $p/cmdline 2>/dev/null)"; done; }
{
  names
  k=0
  while [ $k -le $N ]; do
    echo "@@ $k"
    cat /proc/uptime
    cat /proc/stat
    echo "@@procs"
    cat /proc/[0-9]*/stat 2>/dev/null
    echo "@@end"
    [ $k -lt $N ] && sleep $I
    k=$((k+1))
  done
  names
  echo DONE
} > $OUT 2>/dev/null
