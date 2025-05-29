#!/bin/bash
set -e

USER_NAME=$(whoami)

echo "🚀 安裝必要套件..."
sudo apt update
sudo apt install -y wmctrl xdotool libnotify-bin

echo "📂 建立主關閉腳本 /usr/local/bin/graceful-shutdown-all.sh ..."
sudo tee /usr/local/bin/graceful-shutdown-all.sh > /dev/null << 'EOF'
#!/bin/bash
MODE=$1
USER_NAME=$(whoami)
COUNTDOWN=10

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus notify-send \
        "⚠ 系統即將 $MODE" \
        "所有應用程式將於 $COUNTDOWN 秒後被自動關閉…" \
        --icon=system-shutdown --urgency=critical
    fi
}

countdown() {
    for ((i=$COUNTDOWN; i>0; i--)); do
        echo "⚠️  $i 秒後將 $MODE，按 Ctrl+C 中斷。"
        sleep 1
    done
}

if [ "$MODE" == "shutdown" ]; then
    echo "[0/7] 提早 sync 磁碟寫入"
    sync

    echo "[1/7] 卸載所有非系統掛載點"
    mount | grep "^/dev" | awk '{print $3}' | grep -vE "^/$" | xargs -r sudo umount -l
fi

echo "[2/7] 通知使用者 + 倒數計時..."
notify
countdown

echo "[3/7] 嘗試關閉視窗（wmctrl -c）"
if command -v wmctrl &>/dev/null; then
  wmctrl -l | awk '{print $1}' | while read -r wid; do
    wmctrl -ic "$wid"
  done
fi
sleep 5

echo "[4/7] 先優先關閉 Chrome"
PIDS=$(pgrep -u "$USER_NAME" -f chrome)
if [ -n "$PIDS" ]; then
  kill -15 $PIDS
  sleep 8
fi

echo "[5/7] 發送 SIGTERM 關閉其他桌面程式..."
PIDS=$(ps -u "$USER_NAME" -o pid=,comm= | awk '$2 !~ /^(bash|systemd|dbus|init|loginctl|graceful-shutdown-all.sh|chrome)$/' | awk '{print $1}' | grep -v $$)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs -r kill -15
  sleep 8
fi

echo "[6/7] 強制關閉殘留程式 (SIGKILL)..."
PIDS=$(ps -u "$USER_NAME" -o pid= | grep -v $$)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs -r kill -9
fi

echo "[7/7] 同步磁碟寫入 (sync)..."
sync

if [ "$MODE" == "shutdown" ]; then
  echo "[8/7] 若為 root，自動關機"
  [[ $EUID -eq 0 ]] && systemctl poweroff
fi
EOF

sudo chmod +x /usr/local/bin/graceful-shutdown-all.sh

echo "🧷 建立使用者登出服務 ~/.config/systemd/user/graceful-exit.service ..."
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/graceful-exit.service <<EOF
[Unit]
Description=Graceful shutdown of user applications on logout
Before=exit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh logout
TimeoutSec=30
RemainAfterExit=true

[Install]
WantedBy=exit.target
EOF

systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable graceful-exit.service

echo "🧷 建立系統關機服務 /etc/systemd/system/graceful-shutdown.service ..."
sudo tee /etc/systemd/system/graceful-shutdown.service > /dev/null <<EOF
[Unit]
Description=Gracefully shutdown all user applications before shutdown
DefaultDependencies=no
Before=poweroff.target reboot.target halt.target
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh shutdown
RemainAfterExit=true
TimeoutSec=60

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service

echo "✅ 安裝完成！下次登出或關機會自動優雅關閉應用程式。"
