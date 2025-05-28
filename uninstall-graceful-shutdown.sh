#!/bin/bash
set -e

echo "🔧 正在停用並移除 graceful-shutdown..."

# 停用 systemd 服務
systemctl --user disable graceful-exit.service 2>/dev/null || true
systemctl disable graceful-shutdown.service 2>/dev/null || true

# 移除服務檔案
rm -f ~/.config/systemd/user/graceful-exit.service
sudo rm -f /etc/systemd/system/graceful-shutdown.service

# 移除主腳本
sudo rm -f /usr/local/bin/graceful-shutdown-all.sh

# 重新載入 systemd
systemctl --user daemon-reexec
systemctl --user daemon-reload
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

echo "✅ graceful-shutdown 已成功解除安裝。"
