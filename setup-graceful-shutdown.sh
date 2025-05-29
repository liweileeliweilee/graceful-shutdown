#!/bin/bash
set -e

echo "🚀 安裝必要套件..."
sudo apt update
sudo apt install -y wmctrl xdotool libnotify-bin

echo "📂 建立主關閉腳本..."
sudo tee /usr/local/bin/graceful-shutdown-all.sh > /dev/null << 'EOF'
#!/bin/bash
USER_NAME=$(logname)
COUNTDOWN=10
IS_SHUTDOWN=0

notify() {
    DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$USER_NAME")/bus \
    notify-send "⚠ 系統即將關機或登出" "所有應用程式將於 $COUNTDOWN 秒後被自動關閉…" --icon=system-shutdown --urgency=critical || true
}

countdown() {
    for ((i=$COUNTDOWN; i>0; i--)); do
        echo "⚠️  $i 秒後將關閉所有應用程式，可按 Ctrl+C 中斷此操作。"
        sleep 1
    done
}

sync_disks() {
    echo "[4/7] 預先同步磁碟寫入 (sync)..."
    sync
}

close_chrome() {
    echo "[1/7] 嘗試模擬 Ctrl+Shift+Q 關閉 Chrome..."
    CHROME_WID=$(xdotool search --onlyvisible --class "chrome" | head -n 1)
    if [ -n "$CHROME_WID" ]; then
        xdotool windowfocus "$CHROME_WID"
        xdotool key --clearmodifiers ctrl+shift+q
        sleep 4
    fi
}

close_windows() {
    echo "[2/7] 嘗試關閉其他視窗（wmctrl -c）"
    wmctrl -l | awk '{print $1}' | while read -r wid; do
        wmctrl -ic "$wid"
    done
    sleep 4
}

terminate_apps() {
    echo "[3/7] 發送 SIGTERM..."
    PIDS=$(ps -u "$USER_NAME" -o pid=,comm= | awk '$2 !~ /^(bash|systemd|graceful-shutdown-all.sh)$/ {print $1}')
    if [ -n "$PIDS" ]; then
        echo "$PIDS" | xargs -r kill -15
        sleep 8
    fi
}

force_kill() {
    echo "[5/7] 強制關閉殘留程式 (SIGKILL)..."
    PIDS=$(ps -u "$USER_NAME" -o pid= | grep -v $$)
    [ -n "$PIDS" ] && echo "$PIDS" | xargs -r kill -9
}

try_umount() {
    echo "[6/7] 嘗試 umount 所有 /mnt/pve/* 掛載點..."
    for mp in /mnt/pve/*; do
        mountpoint -q "$mp" && umount -l "$mp"
    done
}

final_action() {
    echo "[7/7] 完成"
    [ "$IS_SHUTDOWN" -eq 1 ] && sync && systemctl poweroff
}

# 判斷是否為關機路徑
[[ "$1" == "--shutdown" ]] && IS_SHUTDOWN=1

notify
countdown
sync_disks
close_chrome
close_windows
terminate_apps
force_kill
[ "$IS_SHUTDOWN" -eq 1 ] && try_umount
final_action
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
TimeoutSec=45
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
Description=Gracefully shutdown all user applications before system shutdown
DefaultDependencies=no
Before=poweroff.target reboot.target halt.target
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh --shutdown
RemainAfterExit=true
TimeoutSec=60

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service

echo "✅ 安裝完成！下次登出或關機會自動優雅關閉應用程式。"
