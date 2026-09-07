# tvhome

最小 Android TV launcher：一個 GridView 列出所有 TV app（LEANBACK_LAUNCHER），沒有動畫、桌布、
推薦列、常駐服務。常駐記憶體約 30MB（Google TV 首頁 200MB+、Projectivy 80MB）。

原本是給 BenQ GV01 投影機（Android TV 14、2GB RAM）做的，任何 Android TV / Google TV 都能用。

## 需求

- Android TV / Google TV，Android 5.0 以上。不符的裝置（手機、平板、太舊的電視）安裝時會直接被拒
- 電腦上有 adb，電視開啟開發人員選項 → USB / 網路偵錯

想先確認再裝：電視「設定 → 關於 → Android 版本」5.0 以上即可。或用 adb：

```
adb shell getprop ro.build.version.sdk      # ≥ 21
adb shell pm list features | grep leanback  # 有輸出才是 Android TV
```

## 安裝

```
adb connect <電視 IP>
adb install -r app-release.apk
adb shell cmd package set-home-activity --user 0 tw.hungmi.tvhome/.MainActivity
```

按 HOME 鍵就是新首頁。電視沒有「選預設首頁」的 UI，一定要用第三行那個指令。

## 還原

```
adb shell cmd package set-home-activity --user 0 <原本的 launcher>/<activity>
```

原本的 launcher 用這個查：`adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME`。
Google TV 是 `com.google.android.apps.tv.launcherx/.home.HomeActivity`（若被停用要先 `pm enable --user 0`）。

## 操作

D-pad 移動、OK 開 app、HOME 回首頁。「設定」用系統設定 app 那格（齒輪）。
沒有其他功能，也不打算加。HDMI 切換用遙控器的輸入源鍵。

## 編譯

GitHub Actions（`.github/workflows/build.yml`）：push 到 main 就編，artifact `tvhome-apk`。
簽名金鑰放 secrets `KEYSTORE_B64`（PKCS12 base64）、`KEYSTORE_PASSWORD`，alias `tvhome`。
