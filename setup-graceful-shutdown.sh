#!/bin/bash
set -e

echo "🚀 Installing dependencies..."
sudo apt update
sudo apt install -y wmctrl xdotool libnotify-bin

echo "📂 Creating shutdown script..."
sudo tee /usr/local/bin/graceful-shutdown-all.sh > /dev/null << 'EOF'
#!/bin/bash
USER_NAME=$(whoami)
COUNTDOWN=10

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus notify-send \
            "⚠ 系統即將關機或登出" \
            "所有應用程式將於 $COUNTDOWN 秒後被自動關閉…" \
            --icon=system-shutdown --urgency=critical
    fi
}

countdown() {
    for ((i=$COUNTDOWN; i>0; i--)); do
        echo "⚠️  $i 秒後將關閉所有應用程式，可按 Ctrl+C 中斷此操作。"
        sleep 1
    done
}

echo "[0/6] 通知使用者 + 倒數計時..."
notify
countdown

echo "[1/6] 嘗試關閉視窗（wmctrl -c）"
if command -v wmctrl &>/dev/null; then
  wmctrl -l | awk '{print $1}' | while read -r wid; do
    wmctrl -ic "$wid"
  done
fi
sleep 5

echo "[2/6] 發送 SIGTERM 關閉桌面程式..."
PIDS=$(ps -u "$USER_NAME" -o pid=,comm= | awk '$2 !~ /^(bash|systemd|dbus|init|loginctl|graceful-shutdown-all.sh)$/' | awk '{print $1}' | grep -v $$)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs -r kill -15
  sleep 5
fi

echo "[3/6] 強制關閉殘留程式 (SIGKILL)..."
PIDS=$(ps -u "$USER_NAME" -o pid= | grep -v $$)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs -r kill -9
fi

echo "[4/6] 同步磁碟寫入 (sync)..."
sync

echo "[5/6] 結束：自動關機（若為 root）或等待 systemd 處理"
[[ $EUID -eq 0 ]] && systemctl poweroff
EOF

sudo chmod +x /usr/local/bin/graceful-shutdown-all.sh

echo "🧷 Installing user logout service..."
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/graceful-exit.service <<EOF
[Unit]
Description=Graceful shutdown of user applications on logout
Before=exit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh
TimeoutSec=30
RemainAfterExit=true

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable graceful-exit.service

echo "🧷 Installing system shutdown service..."
sudo tee /etc/systemd/system/graceful-shutdown.service > /dev/null <<EOF
[Unit]
Description=Gracefully shutdown all user applications before shutdown
DefaultDependencies=no
Before=poweroff.target reboot.target halt.target
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh
RemainAfterExit=true
TimeoutSec=30

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service

echo "✅ Installation complete. Will gracefully close apps on logout/shutdown."
