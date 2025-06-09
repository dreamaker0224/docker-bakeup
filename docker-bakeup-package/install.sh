#!/bin/bash

set -e

INSTALL_DIR="/usr/local/bin"

echo "🔧 安裝 docker-bakeup 工具中..."

# 檢查使用者是否有權限寫入 INSTALL_DIR
if [ ! -w "$INSTALL_DIR" ]; then
  echo "❌ 需要 sudo 權限安裝到 $INSTALL_DIR"
  exit 1
fi

# 複製執行檔
cp docker-bakeup "$INSTALL_DIR/docker-bakeup"
chmod +x "$INSTALL_DIR/docker-bakeup"

cp backup.sh "$INSTALL_DIR/backup.sh"
chmod +x "$INSTALL_DIR/backup.sh"

cp restore.sh "$INSTALL_DIR/restore.sh"
chmod +x "$INSTALL_DIR/restore.sh"

echo "✅ 安裝完成！你可以使用："
echo "   docker-bakeup backup ..."
echo "   docker-bakeup restore ..."

