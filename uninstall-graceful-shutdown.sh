#!/bin/bash
set -e

echo "🧹 停用並移除使用者登出服務..."
systemctl --user disable graceful-exit.service || true
rm -f ~/.config/systemd/user/graceful-exit.service
systemctl --user daemon-reload

echo "🧹 停用並移除系統關機服務..."
sudo systemctl disable graceful-shutdown.service || true
sudo rm -f /etc/systemd/system/graceful-shutdown.service
sudo systemctl daemon-reload

echo "🧹 移除主關閉腳本..."
sudo rm -f /usr/local/bin/graceful-shutdown-all.sh

echo "✅ 已移除 graceful-shutdown 相關設定與腳本。"
