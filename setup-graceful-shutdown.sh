#!/bin/bash
set -e

echo "🚀 安裝必要套件..."
sudo apt update
sudo apt install -y wmctrl xdotool libnotify-bin

echo "📂 建立卸載掛載點腳本..."
sudo tee /usr/local/bin/unmount-all-guest-mounts.sh > /dev/null << 'EOF'
#!/bin/bash
echo "[graceful-shutdown] 🔌 卸載所有 /mnt/pve/* 掛載點..."

mount | grep '/mnt/pve/' | awk '{print $3}' | while read -r mountpoint; do
  if mountpoint -q "$mountpoint"; then
    echo "↪️ 卸載：$mountpoint"
    umount -fl "$mountpoint" && echo "✅ 成功卸載 $mountpoint" || echo "❌ 無法卸載 $mountpoint"
  fi
done
EOF

sudo chmod +x /usr/local/bin/unmount-all-guest-mounts.sh

echo "📂 建立主關閉腳本..."
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
sleep 3

echo "[2/6] 發送 SIGTERM 關閉桌面程式..."
PIDS=$(ps -u "$USER_NAME" -o pid=,comm= | awk '$2 !~ /^(bash|systemd|dbus|init|loginctl|graceful-shutdown-all.sh)$/' | awk '{print $1}' | grep -v $$)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs -r kill -15
  sleep 3
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

echo "🧷 建立使用者登出服務..."
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
WantedBy=exit.target
EOF

systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable graceful-exit.service

echo "🧷 建立系統關機服務..."
sudo tee /etc/systemd/system/graceful-shutdown.service > /dev/null <<EOF
[Unit]
Description=Gracefully shutdown all user applications and unmount guests before shutdown
DefaultDependencies=no
Before=poweroff.target reboot.target halt.target
After=graphical.target

[Service]
Type=oneshot
ExecStartPre=/usr/local/bin/unmount-all-guest-mounts.sh
ExecStart=/usr/local/bin/graceful-shutdown-all.sh
RemainAfterExit=true
TimeoutSec=60

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service

echo "✅ 安裝完成！下次關機或登出將自動卸載 /mnt/pve/* 並優雅關閉應用程式。"
