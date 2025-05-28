# graceful-shutdown

自動優雅關閉所有桌面應用程式，避免 Chrome、Firefox 等出現「上次未正常關閉」提示。

## 🚀 一鍵安裝指令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的帳號/graceful-shutdown/main/setup-graceful-shutdown.sh)
```
## 🚀 一鍵解除安裝指令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的帳號/graceful-shutdown/main/uninstall-graceful-shutdown.sh)
```

## 功能
- 通知使用者系統即將關閉
- 自動倒數 10 秒
- 嘗試用 `wmctrl` 關閉所有視窗
- 發送 SIGTERM / SIGKILL 關閉應用程式
- 登出與關機時自動觸發

## 相依套件
- wmctrl
- xdotool
- libnotify-bin
