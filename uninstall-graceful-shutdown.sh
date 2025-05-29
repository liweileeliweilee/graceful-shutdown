#!/bin/bash
echo "🧹 移除 graceful-shutdown..."

systemctl --user disable graceful-exit.service 2>/dev/null
rm -f ~/.config/systemd/user/graceful-exit.service

sudo systemctl disable graceful-shutdown.service 2>/dev/null
sudo rm -f /etc/systemd/system/graceful-shutdown.service

sudo rm -f /usr/local/bin/graceful-shutdown-all.sh

systemctl --user daemon-reload
sudo systemctl daemon-reload

echo "✅ 已完成移除。"
