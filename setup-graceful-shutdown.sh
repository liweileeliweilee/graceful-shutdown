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
DSM_VMID=820
DSM_SHUTDOWN_TIMEOUT=600  # 10 分鐘

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
    echo "[4/8] 預先同步磁碟寫入 (sync)..."
    sync
}

close_chrome() {
    echo "[1/8] 嘗試模擬點擊 Chrome 右上角關閉按鈕..."
    CHROME_WID=$(xdotool search --onlyvisible --class "chrome" | head -n 1)
    if [ -n "$CHROME_WID" ]; then
        xdotool windowactivate --sync "$CHROME_WID"
        eval $(xdotool getwindowgeometry --shell "$CHROME_WID")
        xdotool mousemove --sync $((X + WIDTH - 15)) $((Y + 15))
        xdotool click 1
        sleep 5
    fi
}

close_windows() {
    echo "[2/8] 嘗試關閉其他視窗（wmctrl -c）"
    wmctrl -l | awk '{print $1}' | while read -r wid; do
        wmctrl -ic "$wid"
    done
    sleep 4
}

terminate_apps() {
    echo "[3/8] 發送 SIGTERM..."
    PIDS=$(ps -u "$USER_NAME" -o pid=,comm= | awk '$2 !~ /^(bash|systemd|graceful-shutdown-all.sh)$/ {print $1}')
    if [ -n "$PIDS" ]; then
        echo "$PIDS" | xargs -r kill -15
        sleep 8
    fi
}

force_kill() {
    echo "[6/8] 強制關閉殘留程式 (SIGKILL)..."
    PIDS=$(ps -u "$USER_NAME" -o pid= | grep -v $$)
    [ -n "$PIDS" ] && echo "$PIDS" | xargs -r kill -9
}

try_umount() {
    echo "[7/8] 嘗試 umount 所有 /mnt/pve/* 掛載點..."
    for mp in /mnt/pve/*; do
        mountpoint -q "$mp" && umount -l "$mp"
    done
}

shutdown_dsm_vm() {
    echo "[5/8] 主動關閉 DSM VM (VMID=$DSM_VMID) 並等待完成..."
    sudo qm shutdown $DSM_VMID || echo "警告：發送關機指令失敗，可能 VM 未啟動"
    
    local elapsed=0
    while [ $elapsed -lt $DSM_SHUTDOWN_TIMEOUT ]; do
        status=$(sudo qm status $DSM_VMID 2>/dev/null || echo "stopped")
        if [[ "$status" != "running" ]]; then
            echo "DSM VM 已關閉。"
            break
        fi
        echo "等待 DSM VM 關機中，已等候 ${elapsed} 秒..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    if [ $elapsed -ge $DSM_SHUTDOWN_TIMEOUT ]; then
        echo "警告：等待 DSM VM 關機超時 (${DSM_SHUTDOWN_TIMEOUT} 秒)，繼續後續關機程序。"
    fi
}

final_action() {
    echo "[8/8] 完成"
    [ "$IS_SHUTDOWN" -eq 1 ] && sync && systemctl poweroff
}

[[ "$1" == "--shutdown" ]] && IS_SHUTDOWN=1

notify
countdown
close_chrome
close_windows
terminate_apps

if [ "$IS_SHUTDOWN" -eq 1 ]; then
#    shutdown_dsm_vm
    try_umount
fi

force_kill
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
TimeoutSec=720

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service

echo "✅ 安裝完成！下次登出或關機會自動優雅關閉應用程式。"
