#!/usr/bin/env python3
"""分析 bench/measure.sh 的結果。

  python3 bench/analyze.py bench/runs/jal                     單組：每個視窗的 CPU、每秒重畫、記憶體
  python3 bench/analyze.py bench/runs/gtv bench/runs/jal ...  多組：再印 README 的表格、各程序記憶體對照

CPU 用 /proc 的 tick 差（USER_HZ = 100）：
  程序 % = Δ(utime + stime) ÷ (秒數 × 100)，佔一核
  全機 % = 1 − Δ(idle + iowait) ÷ Δ(全部欄位)，佔全部核心
"""
import os
import re
import statistics as st
import sys

HZ = 100


def parse_snap(path):
    names, snaps, cur, mode = {}, [], None, None
    for line in open(path, errors='replace'):
        line = line.rstrip('\n')
        if line.startswith('N '):
            parts = line.split(' ', 2)
            if len(parts) == 3 and parts[2].strip():
                names[parts[1]] = parts[2].strip()
        elif line.startswith('@@ '):
            cur = {'cpu': {}, 'procs': {}}
            snaps.append(cur)
            mode = 'uptime'
        elif line == '@@procs':
            mode = 'procs'
        elif line == '@@end':
            cur['done'] = True
            mode = None
        elif mode == 'uptime':
            cur['uptime'] = float(line.split()[0])
            mode = 'stat'
        elif mode == 'stat' and line.startswith('cpu'):
            f = line.split()
            cur['cpu'][f[0]] = list(map(int, f[1:]))
        elif mode == 'procs':
            m = re.match(r'(\d+) \((.*)\) (.*)', line)
            if m:
                rest = m.group(3).split()
                # 用 (pid, starttime) 當 key，pid 被重複使用也不會算錯
                cur['procs'][(m.group(1), rest[19])] = (m.group(2), int(rest[11]) + int(rest[12]))
    return names, [s for s in snaps if s.get('done')]


def windows(names, snaps):
    rows = []
    for a, b in zip(snaps, snaps[1:]):
        dt = b['uptime'] - a['uptime']
        d = [y - x for x, y in zip(a['cpu']['cpu'], b['cpu']['cpu'])]
        procs = {}
        for key, (comm, t1) in b['procs'].items():
            t0 = a['procs'].get(key, (comm, 0))[1]  # 視窗中途出生的程序從 0 算
            procs[key] = (names.get(key[0], comm).split(' ')[0], (t1 - t0) / (dt * HZ))
        rows.append({'dt': dt, 'total': 1 - (d[3] + d[4]) / sum(d), 'procs': procs})
    return rows


def cpu(row, pred):
    return sum(v for n, v in row['procs'].values() if pred(n))


def gfx(path):
    t = open(path).read()
    return (int(re.search(r'Uptime: (\d+)', t).group(1)),
            sum(map(int, re.findall(r'Total frames rendered: (\d+)', t))),
            re.findall(r'Graphics info for pid (\d+)', t))


def pss_by_process(path):
    """dumpsys meminfo（不帶參數）的 Total PSS by process，單位 MB。"""
    t = open(path).read()
    if 'Total PSS by process:' not in t:
        return {}
    sec = t.split('Total PSS by process:')[1].split('Total PSS by OOM adjustment:')[0]
    out = {}
    for kb, name in re.findall(r'^\s*([\d,]+)K: (\S+) \(pid', sec, re.M):
        out[name] = out.get(name, 0) + int(kb.replace(',', '')) / 1024
    return out


def power(path):
    """欄位名稱各 Android 版本不同，讀不到的回 None，判斷時跳過。"""
    t = open(path).read()
    g = lambda pat: (re.search(pat, t, re.I) or [None, None])[1]
    return g(r'mWakefulness=(\w+)'), g(r'lastUserActivityTime=(\d+)'), g(r'mCurrentDream\w*=(\S+)')


def cores(n):
    return '一兩三四五六七八'[n - 1] if 1 <= n <= 8 else str(n)


def analyze(run):
    pkg = open(os.path.join(run, 'pkg')).read().strip()
    names, snaps = parse_snap(os.path.join(run, 'snap.out'))
    rows = windows(names, snaps)
    is_pkg = lambda n: n == pkg or n.startswith(pkg + ':')
    r = {'label': os.path.basename(run.rstrip('/')), 'pkg': pkg, 'warn': []}
    r['home'] = [cpu(w, is_pkg) for w in rows]
    r['sf'] = [cpu(w, lambda n: n.endswith('surfaceflinger')) for w in rows]
    r['hal'] = [cpu(w, lambda n: 'composer' in n) for w in rows]
    r['total'] = [w['total'] for w in rows]
    r['ncpu'] = max((sum(1 for k in s['cpu'] if k != 'cpu') for s in snaps), default=0)

    agg = {}
    for w in rows:
        for n, v in w['procs'].values():
            agg[n] = agg.get(n, 0) + v / len(rows)
    r['top'] = sorted(((v, n) for n, v in agg.items()), reverse=True)[:10]

    (ua, fa, pa), (ub, fb, pb) = gfx(os.path.join(run, 'gfxA.txt')), gfx(os.path.join(run, 'gfxB.txt'))
    r['fps'], r['frames'], r['fsec'] = (fb - fa) / ((ub - ua) / 1000), fb - fa, (ub - ua) / 1000
    if pa != pb:
        r['warn'].append(f'量測中首頁程序換了（pid {pa} → {pb}），每秒重畫不準')

    txt = open(os.path.join(run, 'meminfo_pkg.txt')).read()
    r['mem'] = [(name, int(pss) / 1024, int(swap) / 1024) for name, pss, swap in re.findall(
        r'MEMINFO in pid \d+ \[(.*?)\] \*\*.*?TOTAL PSS:\s+(\d+).*?TOTAL SWAP[^:]*:\s+(\d+)', txt, re.S)]
    r['pss_all'] = pss_by_process(os.path.join(run, 'meminfo_all.txt'))

    (wa, aa, da), (wb, ab, db) = power(os.path.join(run, 'power_before.txt')), power(os.path.join(run, 'power_after.txt'))
    if any(w not in (None, 'Awake') for w in (wa, wb)) or any(d not in (None, 'null') for d in (da, db)):
        r['warn'].append('螢保或待機啟動過，這組作廢')
    if aa and ab and aa != ab:
        r['warn'].append('量測中有人按了遙控器，這組作廢')
    if len(rows) == 0:
        r['warn'].append('snap.out 沒有完整視窗')
    r['dts'] = [w['dt'] for w in rows]
    return r


def pct(v):
    v *= 100
    return f'{v:.0f}%' if v >= 5 else (f'{v:.1f}%' if v >= 0.05 else '0%')


def mean(xs):
    return st.mean(xs) if xs else 0


def print_run(r):
    print(f"== {r['label']}（{r['pkg']}）{len(r['dts'])} 個視窗，各 {', '.join(f'{d:.1f}' for d in r['dts'])} 秒")
    print(f"{'':20}" + ''.join(f'  W{i + 1:<5}' for i in range(len(r['dts']))) + '   平均')
    for label, key in (('首頁程序（含副程序）', 'home'), ('surfaceflinger', 'sf'), ('composer HAL', 'hal'),
                       (f"全機（{cores(r['ncpu'])}核）", 'total')):
        print(f'{label:20}' + ''.join(f'  {v * 100:5.1f}%' for v in r[key]) + f'  {mean(r[key]) * 100:5.1f}%')
    print(f"每秒重畫 {r['fps']:.2f}（{r['frames']} 幀 / {r['fsec']:.1f} 秒）")
    total = sum(p for _, p, _ in r['mem'])
    print(f"記憶體 {total:.1f}MB = " + ' + '.join(f'{n} {p:.1f}（swap {s:.1f}）' for n, p, s in r['mem']))
    short = lambda n: os.path.basename(n) if n.startswith('/') else n
    print('CPU 前 10 名（佔一核）：' + '、'.join(f'{short(n)} {v * 100:.1f}%' for v, n in r['top']))
    for w in r['warn']:
        print(f'⚠ {w}')
    print()


def print_compare(rs):
    print('| 閒置 | ' + ' | '.join(r['label'] for r in rs) + ' |')
    print('|---' * (len(rs) + 1) + '|')
    print('| 記憶體（PSS，含副程序與 swap） | ' + ' | '.join(f"{sum(p for _, p, _ in r['mem']):.0f}MB" for r in rs) + ' |')
    print('| 首頁程序 CPU（佔一核） | ' + ' | '.join(pct(mean(r['home'])) for r in rs) + ' |')
    print('| 畫面合成 surfaceflinger（佔一核） | ' + ' | '.join(pct(mean(r['sf'])) for r in rs) + ' |')
    n = {r['ncpu'] for r in rs}
    print(f"| **全機 CPU（{cores(n.pop()) + '核' if len(n) == 1 else '全部核心'}）** | "
          + ' | '.join(f"**{pct(mean(r['total']))}**" for r in rs) + ' |')
    print('| 每秒重畫 | ' + ' | '.join(f"{r['fps']:.0f}" for r in rs) + ' |')
    print()
    # 首頁叫起來的其他 app 不算在它套件名下，這裡才看得到（例如 Google TV 首頁帶起 HBO Max）
    names = set().union(*(r['pss_all'] for r in rs))
    diff = sorted(((max(r['pss_all'].get(n, 0) for r in rs) - min(r['pss_all'].get(n, 0) for r in rs), n) for n in names),
                  reverse=True)
    print('各組相差超過 4MB 的程序（PSS，MB）：')
    print(f"{'':50}" + ''.join(f'{r["label"][:9]:>10}' for r in rs))
    for d, n in diff:
        if d < 4:
            break
        print(f'{n[:50]:50}' + ''.join(f"{r['pss_all'].get(n, 0):10.1f}" for r in rs))
    print(f"{'全機合計':46}" + ''.join(f"{sum(r['pss_all'].values()):10.0f}" for r in rs))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    results = [analyze(run) for run in sys.argv[1:]]
    for r in results:
        print_run(r)
    if len(results) > 1:
        print_compare(results)
