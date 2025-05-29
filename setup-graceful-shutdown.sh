#!/bin/bash

set -e

install_path="/usr/local/bin/graceful-shutdown-all.sh"
service_path="/etc/systemd/system/graceful-shutdown.service"

# 寫入主腳本
cat << 'EOF' | sudo tee "$install_path" > /dev/null
#!/bin/bash
# graceful-shutdown-all.sh

echo -e "\n[0/6] 通知使用者 + 倒數計時..."
sudo -u liweilee DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
  zenity --info --text="⚠️ 系統即將關機，所有應用程式將被自動關閉。" --timeout=10 || true

for i in {10..1}; do
  echo "⚠️  $i 秒後將關閉所有應用程式，可按 Ctrl+C 中斷此操作。"
  sleep 1
done

echo -e "\n[1/6] 提早 sync 資料..."
sync

echo -e "\n[2/6] 優先關閉 Google Chrome..."
pkill -15 chrome || true
sleep 8
pkill -9 chrome || true

echo -e "\n[3/6] 關閉其他常見應用程式..."
pkill -15 smplayer || true
sleep 5
pkill -9 smplayer || true

echo -e "\n[4/6] 主動關閉 DSM 虛擬機 (VMID 820)..."
qm shutdown 820 || true

for i in {1..60}; do
  if ! qm status 820 | grep -q "status: running"; then
    echo "✅ DSM 已關機"
    break
  fi
  echo "⏳ 等待 DSM 關機中（$i 秒）..."
  sleep 1
done

echo -e "\n[5/6] 卸載所有非系統掛載點..."
mount | grep "^/dev" | grep -vE "/(boot|efi|/)$" | awk '{print $3}' | tac | while read -r mountpoint; do
  echo "🔌 卸載 $mountpoint"
  umount -lf "$mountpoint" 2>/dev/null || echo "⚠️ 無法卸載 $mountpoint"
done

echo -e "\n[6/6] 再次 sync，完成收尾..."
sync
EOF

# 權限設定
sudo chmod +x "$install_path"

# 建立 systemd 服務
cat << EOF | sudo tee "$service_path" > /dev/null
[Unit]
Description=Gracefully shutdown all user applications before system shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/graceful-shutdown-all.sh
RemainAfterExit=true

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

# 重新載入 systemd 並啟用服務
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable graceful-shutdown.service
