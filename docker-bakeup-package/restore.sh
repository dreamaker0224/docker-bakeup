#!/bin/bash

# 檢查是否以 root 權限運行
if [ "$EUID" -ne 0 ]; then
  echo "錯誤：請以 sudo 執行此腳本 (sudo ./restore.sh)"
  exit 1
fi

# 檢查參數
if [ $# -lt 1 ]; then
  echo "用法: $0 <備份目錄路徑> [還原目錄路徑] [選項]"
  echo ""
  echo "範例:"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 /home/user/projects"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 . --project-only"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 /home/user/projects --volumes-only"
  echo ""
  echo "參數說明:"
  echo "  <備份目錄路徑>     必需：包含備份資料的目錄"
  echo "  [還原目錄路徑]     可選：專案要還原到的目錄 (預設為當前目錄)"
  echo ""
  echo "選項："
  echo "  --project-only    只還原專案資料夾"
  echo "  --volumes-only    只還原 Docker volumes"
  echo "  --binds-only      只還原 bind mounts"
  echo "  --images-only     只還原容器鏡像"
  echo "  --dry-run         預覽還原操作，不實際執行"
  echo "  --force           強制還原，不詢問確認"
  exit 1
fi

BACKUP_PATH="$1"
RESTORE_BASE_DIR=""
RESTORE_PROJECT=true
RESTORE_VOLUMES=true
RESTORE_BINDS=true
RESTORE_IMAGES=true
DRY_RUN=false
FORCE=false#!/bin/bash

# 檢查是否以 root 權限運行
if [ "$EUID" -ne 0 ]; then
  echo "錯誤：請以 sudo 執行此腳本 (sudo ./restore.sh)"
  exit 1
fi

# 檢查參數
if [ $# -lt 1 ]; then
  echo "用法: $0 <備份目錄路徑> [還原目錄路徑] [選項]"
  echo ""
  echo "範例:"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 /home/user/projects"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 . --project-only"
  echo "  $0 /home/drsite/backup/docker/php_ctf/20250605_143022 /home/user/projects --volumes-only"
  echo ""
  echo "參數說明:"
  echo "  <備份目錄路徑>     必需：包含備份資料的目錄"
  echo "  [還原目錄路徑]     可選：專案要還原到的目錄 (預設為當前目錄)"
  echo ""
  echo "選項："
  echo "  --project-only    只還原專案資料夾"
  echo "  --volumes-only    只還原 Docker volumes"
  echo "  --binds-only      只還原 bind mounts"
  echo "  --images-only     只還原容器鏡像"
  echo "  --dry-run         預覽還原操作，不實際執行"
  echo "  --force           強制還原，不詢問確認"
  exit 1
fi

BACKUP_PATH="$1"
RESTORE_BASE_DIR=""
RESTORE_PROJECT=true
RESTORE_VOLUMES=true
RESTORE_BINDS=true
RESTORE_IMAGES=true
DRY_RUN=false
FORCE=false

# 解析第二個參數（還原目錄）和其他選項
shift
current_arg="$1"

# 檢查第二個參數是否為選項或目錄路徑
if [ -n "$current_arg" ] && [[ ! "$current_arg" =~ ^-- ]]; then
  RESTORE_BASE_DIR="$current_arg"
  shift
fi

# 如果沒有指定還原目錄，使用當前目錄
if [ -z "$RESTORE_BASE_DIR" ]; then
  RESTORE_BASE_DIR="$(pwd)"
fi

# 轉換為絕對路徑
RESTORE_BASE_DIR="$(realpath "$RESTORE_BASE_DIR")"

# 解析其餘選項
while [ $# -gt 0 ]; do
  case $1 in
    --project-only)
      RESTORE_PROJECT=true
      RESTORE_VOLUMES=false
      RESTORE_BINDS=false
      RESTORE_IMAGES=false
      ;;
    --volumes-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=true
      RESTORE_BINDS=false
      RESTORE_IMAGES=false
      ;;
    --binds-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=false
      RESTORE_BINDS=true
      RESTORE_IMAGES=false
      ;;
    --images-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=false
      RESTORE_BINDS=false
      RESTORE_IMAGES=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --force)
      FORCE=true
      ;;
    *)
      echo "未知選項: $1"
      exit 1
      ;;
  esac
  shift
done

# 檢查備份目錄是否存在
if [ ! -d "$BACKUP_PATH" ]; then
  echo "錯誤：備份目錄 $BACKUP_PATH 不存在"
  exit 1
fi

# 檢查還原目錄是否存在，不存在則創建
if [ ! -d "$RESTORE_BASE_DIR" ]; then
  echo "還原目錄 $RESTORE_BASE_DIR 不存在，正在創建..."
  mkdir -p "$RESTORE_BASE_DIR" || {
    echo "錯誤：無法創建還原目錄 $RESTORE_BASE_DIR"
    exit 1
  }
fi

# 檢查必要檔案
METADATA="$BACKUP_PATH/metadata.txt"
if [ ! -f "$METADATA" ]; then
  echo "錯誤：找不到 metadata.txt 檔案"
  exit 1
fi

# 從 metadata 讀取原始資訊
if ! grep -q "Project Path:" "$METADATA"; then
  echo "錯誤：metadata.txt 中找不到專案路徑資訊"
  exit 1
fi

ORIGINAL_PROJECT_PATH=$(grep "Project Path:" "$METADATA" | cut -d' ' -f3-)
ORIGINAL_PROJECT_NAME=$(basename "$ORIGINAL_PROJECT_PATH")
DOCKER_DIR="/var/lib/docker"

# 計算新的專案路徑
NEW_PROJECT_PATH="$RESTORE_BASE_DIR/$ORIGINAL_PROJECT_NAME"

# 定義備份子目錄
PROJECT_BACKUP_DIR="$BACKUP_PATH/project"
VOLUMES_BACKUP_DIR="$BACKUP_PATH/volumes"
BINDS_BACKUP_DIR="$BACKUP_PATH/binds"

# 定義臨時還原目錄
CURRENT_DIR=$(basename "$NEW_PROJECT_PATH")
RESTORE_SNAP_TMP="/home/$SUDO_USER/.tmp_restore/${CURRENT_DIR}_restore_tmp"
DOCKER_RESTORE_TMP="/var/lib/docker/.tmp_restore/${CURRENT_DIR}_restore_tmp"

# 獲取專案的備份根目錄（往上兩層到專案名稱層）
PROJECT_BACKUP_ROOT=$(dirname "$(dirname "$BACKUP_PATH")")

echo "=================================================="
echo "Docker 備份還原腳本"
echo "=================================================="
echo "備份來源: $BACKUP_PATH"
echo "原始專案路徑: $ORIGINAL_PROJECT_PATH"
echo "還原基礎目錄: $RESTORE_BASE_DIR"
echo "新專案路徑: $NEW_PROJECT_PATH"
echo "專案備份根目錄: $PROJECT_BACKUP_ROOT"
echo ""

# 顯示還原計劃
echo "還原計劃:"
if [ "$RESTORE_PROJECT" = true ]; then
  echo "  ✓ 專案資料夾: $NEW_PROJECT_PATH"
fi
if [ "$RESTORE_VOLUMES" = true ]; then
  echo "  ✓ Docker Volumes"
fi
if [ "$RESTORE_BINDS" = true ]; then
  echo "  ✓ Bind Mounts"
fi
if [ "$RESTORE_IMAGES" = true ]; then
  echo "  ✓ 容器鏡像"
fi
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "【預覽模式】以下操作將會執行："
  echo ""
fi

# 檢查 Docker 守護進程是否運行
if ! docker info >/dev/null 2>&1; then
  echo "錯誤：Docker 守護進程未運行，請啟動 Docker (sudo systemctl start docker)"
  exit 1
fi

# 創建臨時還原目錄
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$RESTORE_SNAP_TMP" || {
    echo "創建臨時還原目錄失敗"; exit 1;
  }
  mkdir -p "$DOCKER_RESTORE_TMP" || {
    echo "創建 Docker 臨時還原目錄失敗"; exit 1;
  }
fi

# 判斷路徑是否為 btrfs subvolume
is_subvolume() {
  local path=$1
  if [ ! -e "$path" ]; then
    return 1
  fi
  local inode=$(stat -c '%i' "$path")
  if [ "$inode" = "256" ]; then
    return 0
  else
    return 1
  fi
}

# 查找父快照（用於增量備份）
find_parent_backup() {
  local backup_dir=$1
  local component_type=$2  # project, volumes, binds
  
  echo "  尋找父快照..."
  
  # 獲取當前時間戳
  local current_timestamp=$(basename "$BACKUP_PATH")
  
  # 列出所有時間戳目錄並排序（排除當前目錄）
  local backup_timestamps=()
  while IFS= read -r -d '' dir; do
    local timestamp=$(basename "$dir")
    if [ "$timestamp" != "$current_timestamp" ] && [ "$timestamp" != "." ] && [ "$timestamp" != ".." ]; then
      backup_timestamps+=("$timestamp")
    fi
  done < <(find "$PROJECT_BACKUP_ROOT" -maxdepth 1 -type d -print0 | sort -z)
  
  # 按時間戳排序（找最近的完整備份）
  IFS=$'\n' sorted_timestamps=($(sort -r <<< "${backup_timestamps[*]}"))
  
  for timestamp in "${sorted_timestamps[@]}"; do
    local potential_parent="$PROJECT_BACKUP_ROOT/$timestamp/$component_type"
    if [ -d "$potential_parent" ]; then
      # 檢查是否有完整備份
      local full_backup=$(find "$potential_parent" -name "full*.btrfs.gz" -type f | head -n 1)
      if [ -n "$full_backup" ]; then
        echo "    找到父備份: $timestamp (完整備份)"
        echo "$potential_parent"
        return 0
      fi
    fi
  done
  
  echo "    未找到父備份"
  return 1
}

# 還原 btrfs 備份（支援完整和增量備份，改進的父快照查找）
restore_btrfs_backup() {
  local backup_dir=$1
  local target_path=$2
  local description=$3
  local temp_dir=$4
  local component_type=$5  # 新增參數：project, volumes, binds
  
  if [ ! -d "$backup_dir" ]; then
    echo "警告：備份目錄 $backup_dir 不存在，跳過 $description"
    return 1
  fi
  
  echo "還原 $description: $target_path"
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [預覽] 將從 $backup_dir 還原到 $target_path"
    # 顯示可用的備份檔案
    local full_backup=$(find "$backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
    local incre_backup=$(find "$backup_dir" -name "incre*.btrfs.gz" -type f | head -n 1)
    if [ -n "$full_backup" ]; then
      echo "    - 完整備份: $(basename "$full_backup")"
    fi
    if [ -n "$incre_backup" ]; then
      echo "    - 增量備份: $(basename "$incre_backup")"
      # 嘗試找父快照
      local parent_backup_dir
      if parent_backup_dir=$(find_parent_backup "$backup_dir" "$component_type"); then
        echo "    - 父快照來源: $parent_backup_dir"
      else
        echo "    - 警告：增量備份但找不到父快照"
      fi
    fi
    return 0
  fi
  
  # 確保目標目錄的父目錄存在
  local parent_dir=$(dirname "$target_path")
  mkdir -p "$parent_dir" || {
    echo "錯誤：無法建立父目錄 $parent_dir"
    return 1
  }
  
  # 確保臨時目錄存在
  mkdir -p "$temp_dir" || {
    echo "錯誤：無法建立臨時目錄 $temp_dir"
    return 1
  }
  
  # 如果目標路徑存在，先備份
  if [ -e "$target_path" ]; then
    local backup_suffix=$(date +%Y%m%d_%H%M%S)
    local backup_target="${target_path}.backup_${backup_suffix}"
    echo "  目標路徑已存在，備份到: $backup_target"
    mv "$target_path" "$backup_target" || {
      echo "錯誤：無法備份現有路徑"
      return 1
    }
  fi
  
  # 查找備份檔案
  local full_backup=$(find "$backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
  local incre_backup=$(find "$backup_dir" -name "incre*.btrfs.gz" -type f | head -n 1)
  
  # 優先使用完整備份
  if [ -n "$full_backup" ]; then
    echo "  使用完整備份還原: $(basename "$full_backup")"
    if ! gunzip -c "$full_backup" | btrfs receive "$temp_dir" ; then
      echo "錯誤：完整備份還原失敗"
      return 1
    fi
  elif [ -n "$incre_backup" ]; then
    echo "  處理增量備份: $(basename "$incre_backup")"
    
    # 查找父快照
    local parent_backup_dir
    if parent_backup_dir=$(find_parent_backup "$backup_dir" "$component_type"); then
      echo "  找到父備份目錄: $parent_backup_dir"
      
      # 先還原父快照
      local parent_full_backup=$(find "$parent_backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
      if [ -n "$parent_full_backup" ]; then
        echo "  首先還原父快照: $(basename "$parent_full_backup")"
        if ! gunzip -c "$parent_full_backup" | btrfs receive "$temp_dir" ; then
          echo "錯誤：父快照還原失敗"
          return 1
        fi
        
        # 然後應用增量備份
        echo "  應用增量備份: $(basename "$incre_backup")"
        if ! gunzip -c "$incre_backup" | btrfs receive "$temp_dir" 2>/dev/null; then
          echo "錯誤：增量備份應用失敗"
          return 1
        fi
      else
        echo "錯誤：在父備份目錄中找不到完整備份"
        return 1
      fi
    else
      echo "錯誤：增量備份需要父快照，但找不到適合的父備份"
      echo "建議："
      echo "1. 檢查是否有更早的完整備份"
      echo "2. 確保備份目錄結構正確"
      echo "3. 考慮從最新的完整備份開始還原"
      return 1
    fi
  else
    echo "錯誤：在 $backup_dir 中找不到備份檔案"
    echo "支援的備份檔案格式："
    echo "  - full.*.btrfs.gz (完整備份)"
    echo "  - incre.*.btrfs.gz (增量備份)"
    return 1
  fi
  
  # 查找還原後的 subvolume 並移動到目標位置
  # 對於增量備份，我們需要找到最新的 subvolume
  local restored_subvol
  if [ -n "$incre_backup" ]; then
    # 增量備份：找到最新的 subvolume（通常是最後修改的）
    restored_subvol=$(find "$temp_dir" -maxdepth 1 -type d -name "*snap*" | xargs -r ls -td | head -n 1)
  else
    # 完整備份：找到第一個 subvolume
    restored_subvol=$(find "$temp_dir" -maxdepth 1 -type d -name "*snap*" | head -n 1)
  fi
  
  if [ -n "$restored_subvol" ]; then
    echo "  設置 subvolume 為可寫"
    btrfs property set -fts "$restored_subvol" ro false || {
      echo "警告：無法設置 subvolume 為可寫，嘗試繼續"
    }
    
    echo "  移動還原的 subvolume 到目標位置"
    mv "$restored_subvol" "$target_path" || {
      echo "錯誤：無法移動還原的 subvolume"
      return 1
    }
  else
    echo "錯誤：找不到還原的 subvolume"
    echo "臨時目錄內容："
    ls -la "$temp_dir" || true
    return 1
  fi
  
  echo "  $description 還原完成"
  return 0
}

# 還原容器鏡像
restore_images() {
  echo "=================================================="
  echo "還原容器鏡像"
  echo "=================================================="
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [預覽] 將從 Registry 拉取鏡像"
    grep "image:" "$METADATA" | while read -r line; do
      image_info=$(echo "$line" | cut -d':' -f2-)
      echo "    - $image_info"
    done
    return 0
  fi
  
  # 從 metadata 中讀取鏡像資訊並拉取
  grep "image:" "$METADATA" | while read -r line; do
    image_info=$(echo "$line" | cut -d':' -f2- | xargs)
    if [ -n "$image_info" ]; then
      echo "  拉取鏡像: $image_info"
      docker pull "$image_info" || {
        echo "警告：拉取鏡像 $image_info 失敗"
        continue
      }
      
      # 提取容器名稱和版本，創建本地標籤
      container_name=$(echo "$image_info" | cut -d'/' -f2 | cut -d':' -f1)
      version=$(echo "$image_info" | cut -d':' -f3)
      
      if [ -n "$container_name" ] && [ -n "$version" ]; then
        docker tag "$image_info" "${container_name}:latest" || {
          echo "警告：為鏡像 $image_info 創建標籤失敗"
        }
        echo "  鏡像 $container_name 還原完成"
      fi
    fi
  done
}

# 確認還原操作
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
  echo "警告：此操作將會覆蓋現有資料！"
  echo "專案將還原到: $NEW_PROJECT_PATH"
  echo "是否繼續？(y/N)"
  read -r confirmation
  if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
    echo "取消還原操作"
    exit 0
  fi
  echo ""
fi

# 如果要還原專案或 volumes，需要停止 Docker 服務
if [ "$RESTORE_PROJECT" = true ] || [ "$RESTORE_VOLUMES" = true ]; then
  # 檢查是否有 docker-compose.yaml 來停止服務（先檢查新位置，再檢查原位置）
  compose_file=""
  if [ -f "$NEW_PROJECT_PATH/docker-compose.yaml" ]; then
    compose_file="$NEW_PROJECT_PATH/docker-compose.yaml"
  elif [ -f "$ORIGINAL_PROJECT_PATH/docker-compose.yaml" ]; then
    compose_file="$ORIGINAL_PROJECT_PATH/docker-compose.yaml"
  fi
  
  if [ -n "$compose_file" ]; then
    echo "停止 Docker Compose 服務..."
    if [ "$DRY_RUN" = false ]; then
      compose_dir=$(dirname "$compose_file")
      cd "$compose_dir" || {
        echo "警告：無法進入專案目錄，跳過停止服務"
      }
      docker compose stop 2>/dev/null || echo "警告：停止服務失敗或無服務運行"
    else
      echo "  [預覽] 將停止 Docker Compose 服務"
    fi
  fi
fi

# 1. 還原專案資料夾
if [ "$RESTORE_PROJECT" = true ]; then
  echo "=================================================="
  echo "還原專案資料夾"
  echo "=================================================="
  
  restore_btrfs_backup "$PROJECT_BACKUP_DIR" "$NEW_PROJECT_PATH" "專案資料夾" "$RESTORE_SNAP_TMP" "project"
fi

# 2. 還原 Docker Volumes
if [ "$RESTORE_VOLUMES" = true ]; then
  echo "=================================================="
  echo "還原 Docker Volumes"
  echo "=================================================="
  
  if [ -d "$VOLUMES_BACKUP_DIR" ]; then
    for volume_backup_dir in "$VOLUMES_BACKUP_DIR"/*; do
      if [ -d "$volume_backup_dir" ]; then
        # 從目錄名提取 volume 名稱
        volume_name=$(basename "$volume_backup_dir")
        volume_path="$DOCKER_DIR/volumes/$volume_name/_data"
        
        restore_btrfs_backup "$volume_backup_dir" "$volume_path" "Volume $volume_name" "$DOCKER_RESTORE_TMP" "volumes/$volume_name"
      fi
    done
  else
    echo "警告：找不到 volumes 備份目錄"
  fi
fi

# 3. 還原 Bind Mounts
if [ "$RESTORE_BINDS" = true ]; then
  echo "=================================================="
  echo "還原 Bind Mounts"
  echo "=================================================="
  
  if [ -d "$BINDS_BACKUP_DIR" ]; then
    # 從 metadata 中讀取 bind mount 對應關係
    echo "正在分析 bind mount 對應關係..."
    
    for bind_backup_dir in "$BINDS_BACKUP_DIR"/*; do
      if [ -d "$bind_backup_dir" ]; then
        # 從目錄名提取編碼名稱
        encoded_name=$(basename "$bind_backup_dir")
        
        # 從 metadata 中查找對應的原始路徑
        original_path=$(grep "發現 bind mount:" "$METADATA" | grep " -> $encoded_name" | cut -d':' -f2 | cut -d' ' -f2)
        
        if [ -n "$original_path" ]; then
          restore_btrfs_backup "$bind_backup_dir" "$original_path" "Bind mount $original_path" "$RESTORE_SNAP_TMP" "binds/$encoded_name"
        else
          echo "警告：無法找到編碼名稱 $encoded_name 對應的原始路徑"
          if [ "$DRY_RUN" = false ]; then
            echo "可以嘗試手動解碼："
            echo "  編碼名稱: $encoded_name"
            echo "  解碼命令: echo '$encoded_name' | tr '_-' '/+' | base64 -d"
          fi
        fi
      fi
    done
  else
    echo "警告：找不到 binds 備份目錄"
  fi
fi

# 4. 還原容器鏡像
if [ "$RESTORE_IMAGES" = true ]; then
  restore_images
fi

# 重啟服務
if [ "$RESTORE_PROJECT" = true ] || [ "$RESTORE_VOLUMES" = true ]; then
  if [ -f "$NEW_PROJECT_PATH/docker-compose.yaml" ]; then
    echo "=================================================="
    echo "重新啟動 Docker Compose 服務"
    echo "=================================================="
    
    if [ "$DRY_RUN" = false ]; then
      cd "$NEW_PROJECT_PATH" || {
        echo "錯誤：無法進入專案目錄"
        exit 1
      }
      docker compose up -d || {
        echo "警告：重啟服務失敗，請手動檢查"
      }
    else
      echo "  [預覽] 將重新啟動 Docker Compose 服務"
    fi
  fi
fi

# 清理臨時目錄
if [ "$DRY_RUN" = false ]; then
  echo "清理臨時還原目錄..."
  rm -rf "$RESTORE_SNAP_TMP" 2>/dev/null || echo "清理臨時還原目錄失敗"
  rm -rf "$DOCKER_RESTORE_TMP" 2>/dev/null || echo "清理 Docker 臨時還原目錄失敗"
fi

echo "=================================================="
if [ "$DRY_RUN" = true ]; then
  echo "預覽完成！"
  echo "如要執行實際還原，請移除 --dry-run 選項"
else
  echo "還原完成！"
  echo ""
  echo "還原資訊："
  echo "  專案位置: $NEW_PROJECT_PATH"
  echo "  還原基礎目錄: $RESTORE_BASE_DIR"
  echo ""
  echo "注意事項："
  echo "1. 請檢查服務是否正常運行"
  echo "2. 如有問題，原始資料已備份為 *.backup_* 格式"
  echo "3. 詳細還原資訊請查看上述輸出"
  echo "4. 容器鏡像已從 Registry 拉取並重新標籤"
fi
echo "=================================================="

exit 0


# 解析第二個參數（還原目錄）和其他選項
shift
current_arg="$1"

# 檢查第二個參數是否為選項或目錄路徑
if [ -n "$current_arg" ] && [[ ! "$current_arg" =~ ^-- ]]; then
  RESTORE_BASE_DIR="$current_arg"
  shift
fi

# 如果沒有指定還原目錄，使用當前目錄
if [ -z "$RESTORE_BASE_DIR" ]; then
  RESTORE_BASE_DIR="$(pwd)"
fi

# 轉換為絕對路徑
RESTORE_BASE_DIR="$(realpath "$RESTORE_BASE_DIR")"

# 解析其餘選項
while [ $# -gt 0 ]; do
  case $1 in
    --project-only)
      RESTORE_PROJECT=true
      RESTORE_VOLUMES=false
      RESTORE_BINDS=false
      RESTORE_IMAGES=false
      ;;
    --volumes-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=true
      RESTORE_BINDS=false
      RESTORE_IMAGES=false
      ;;
    --binds-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=false
      RESTORE_BINDS=true
      RESTORE_IMAGES=false
      ;;
    --images-only)
      RESTORE_PROJECT=false
      RESTORE_VOLUMES=false
      RESTORE_BINDS=false
      RESTORE_IMAGES=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --force)
      FORCE=true
      ;;
    *)
      echo "未知選項: $1"
      exit 1
      ;;
  esac
  shift
done

# 檢查備份目錄是否存在
if [ ! -d "$BACKUP_PATH" ]; then
  echo "錯誤：備份目錄 $BACKUP_PATH 不存在"
  exit 1
fi

# 檢查還原目錄是否存在，不存在則創建
if [ ! -d "$RESTORE_BASE_DIR" ]; then
  echo "還原目錄 $RESTORE_BASE_DIR 不存在，正在創建..."
  mkdir -p "$RESTORE_BASE_DIR" || {
    echo "錯誤：無法創建還原目錄 $RESTORE_BASE_DIR"
    exit 1
  }
fi

# 檢查必要檔案
METADATA="$BACKUP_PATH/metadata.txt"
if [ ! -f "$METADATA" ]; then
  echo "錯誤：找不到 metadata.txt 檔案"
  exit 1
fi

# 從 metadata 讀取原始資訊
if ! grep -q "Project Path:" "$METADATA"; then
  echo "錯誤：metadata.txt 中找不到專案路徑資訊"
  exit 1
fi

ORIGINAL_PROJECT_PATH=$(grep "Project Path:" "$METADATA" | cut -d' ' -f3-)
ORIGINAL_PROJECT_NAME=$(basename "$ORIGINAL_PROJECT_PATH")
DOCKER_DIR="/var/lib/docker"

# 計算新的專案路徑
NEW_PROJECT_PATH="$RESTORE_BASE_DIR/$ORIGINAL_PROJECT_NAME"

# 定義備份子目錄
PROJECT_BACKUP_DIR="$BACKUP_PATH/project"
VOLUMES_BACKUP_DIR="$BACKUP_PATH/volumes"
BINDS_BACKUP_DIR="$BACKUP_PATH/binds"

# 定義臨時還原目錄
CURRENT_DIR=$(basename "$NEW_PROJECT_PATH")
RESTORE_SNAP_TMP="/home/$SUDO_USER/.tmp_restore/${CURRENT_DIR}_restore_tmp"
DOCKER_RESTORE_TMP="/var/lib/docker/.tmp_restore/${CURRENT_DIR}_restore_tmp"

# 獲取專案的備份根目錄（往上兩層到專案名稱層）
PROJECT_BACKUP_ROOT=$(dirname "$(dirname "$BACKUP_PATH")")

echo "=================================================="
echo "Docker 備份還原腳本"
echo "=================================================="
echo "備份來源: $BACKUP_PATH"
echo "原始專案路徑: $ORIGINAL_PROJECT_PATH"
echo "還原基礎目錄: $RESTORE_BASE_DIR"
echo "新專案路徑: $NEW_PROJECT_PATH"
echo "專案備份根目錄: $PROJECT_BACKUP_ROOT"
echo ""

# 顯示還原計劃
echo "還原計劃:"
if [ "$RESTORE_PROJECT" = true ]; then
  echo "  ✓ 專案資料夾: $NEW_PROJECT_PATH"
fi
if [ "$RESTORE_VOLUMES" = true ]; then
  echo "  ✓ Docker Volumes"
fi
if [ "$RESTORE_BINDS" = true ]; then
  echo "  ✓ Bind Mounts"
fi
if [ "$RESTORE_IMAGES" = true ]; then
  echo "  ✓ 容器鏡像"
fi
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "【預覽模式】以下操作將會執行："
  echo ""
fi

# 檢查 Docker 守護進程是否運行
if ! docker info >/dev/null 2>&1; then
  echo "錯誤：Docker 守護進程未運行，請啟動 Docker (sudo systemctl start docker)"
  exit 1
fi

# 創建臨時還原目錄
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$RESTORE_SNAP_TMP" || {
    echo "創建臨時還原目錄失敗"; exit 1;
  }
  mkdir -p "$DOCKER_RESTORE_TMP" || {
    echo "創建 Docker 臨時還原目錄失敗"; exit 1;
  }
fi

# 判斷路徑是否為 btrfs subvolume
is_subvolume() {
  local path=$1
  if [ ! -e "$path" ]; then
    return 1
  fi
  local inode=$(stat -c '%i' "$path")
  if [ "$inode" = "256" ]; then
    return 0
  else
    return 1
  fi
}

# 查找父快照（用於增量備份）
find_parent_backup() {
  local backup_dir=$1
  local component_type=$2  # project, volumes, binds
  
  echo "  尋找父快照..."
  
  # 獲取當前時間戳
  local current_timestamp=$(basename "$BACKUP_PATH")
  
  # 列出所有時間戳目錄並排序（排除當前目錄）
  local backup_timestamps=()
  while IFS= read -r -d '' dir; do
    local timestamp=$(basename "$dir")
    if [ "$timestamp" != "$current_timestamp" ] && [ "$timestamp" != "." ] && [ "$timestamp" != ".." ]; then
      backup_timestamps+=("$timestamp")
    fi
  done < <(find "$PROJECT_BACKUP_ROOT" -maxdepth 1 -type d -print0 | sort -z)
  
  # 按時間戳排序（找最近的完整備份）
  IFS=$'\n' sorted_timestamps=($(sort -r <<< "${backup_timestamps[*]}"))
  
  for timestamp in "${sorted_timestamps[@]}"; do
    local potential_parent="$PROJECT_BACKUP_ROOT/$timestamp/$component_type"
    if [ -d "$potential_parent" ]; then
      # 檢查是否有完整備份
      local full_backup=$(find "$potential_parent" -name "full*.btrfs.gz" -type f | head -n 1)
      if [ -n "$full_backup" ]; then
        echo "    找到父備份: $timestamp (完整備份)"
        echo "$potential_parent"
        return 0
      fi
    fi
  done
  
  echo "    未找到父備份"
  return 1
}

# 還原 btrfs 備份（支援完整和增量備份，改進的父快照查找）
restore_btrfs_backup() {
  local backup_dir=$1
  local target_path=$2
  local description=$3
  local temp_dir=$4
  local component_type=$5  # 新增參數：project, volumes, binds
  
  if [ ! -d "$backup_dir" ]; then
    echo "警告：備份目錄 $backup_dir 不存在，跳過 $description"
    return 1
  fi
  
  echo "還原 $description: $target_path"
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [預覽] 將從 $backup_dir 還原到 $target_path"
    # 顯示可用的備份檔案
    local full_backup=$(find "$backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
    local incre_backup=$(find "$backup_dir" -name "incre*.btrfs.gz" -type f | head -n 1)
    if [ -n "$full_backup" ]; then
      echo "    - 完整備份: $(basename "$full_backup")"
    fi
    if [ -n "$incre_backup" ]; then
      echo "    - 增量備份: $(basename "$incre_backup")"
      # 嘗試找父快照
      local parent_backup_dir
      if parent_backup_dir=$(find_parent_backup "$backup_dir" "$component_type"); then
        echo "    - 父快照來源: $parent_backup_dir"
      else
        echo "    - 警告：增量備份但找不到父快照"
      fi
    fi
    return 0
  fi
  
  # 確保目標目錄的父目錄存在
  local parent_dir=$(dirname "$target_path")
  mkdir -p "$parent_dir" || {
    echo "錯誤：無法建立父目錄 $parent_dir"
    return 1
  }
  
  # 確保臨時目錄存在
  mkdir -p "$temp_dir" || {
    echo "錯誤：無法建立臨時目錄 $temp_dir"
    return 1
  }
  
  # 如果目標路徑存在，先備份
  if [ -e "$target_path" ]; then
    local backup_suffix=$(date +%Y%m%d_%H%M%S)
    local backup_target="${target_path}.backup_${backup_suffix}"
    echo "  目標路徑已存在，備份到: $backup_target"
    mv "$target_path" "$backup_target" || {
      echo "錯誤：無法備份現有路徑"
      return 1
    }
  fi
  
  # 查找備份檔案
  local full_backup=$(find "$backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
  local incre_backup=$(find "$backup_dir" -name "incre*.btrfs.gz" -type f | head -n 1)
  
  # 優先使用完整備份
  if [ -n "$full_backup" ]; then
    echo "  使用完整備份還原: $(basename "$full_backup")"
    if ! gunzip -c "$full_backup" | btrfs receive "$temp_dir" 2>/dev/null; then
      echo "錯誤：完整備份還原失敗"
      return 1
    fi
  elif [ -n "$incre_backup" ]; then
    echo "  處理增量備份: $(basename "$incre_backup")"
    
    # 查找父快照
    local parent_backup_dir
    if parent_backup_dir=$(find_parent_backup "$backup_dir" "$component_type"); then
      echo "  找到父備份目錄: $parent_backup_dir"
      
      # 先還原父快照
      local parent_full_backup=$(find "$parent_backup_dir" -name "full*.btrfs.gz" -type f | head -n 1)
      if [ -n "$parent_full_backup" ]; then
        echo "  首先還原父快照: $(basename "$parent_full_backup")"
        if ! gunzip -c "$parent_full_backup" | btrfs receive "$temp_dir" 2>/dev/null; then
          echo "錯誤：父快照還原失敗"
          return 1
        fi
        
        # 然後應用增量備份
        echo "  應用增量備份: $(basename "$incre_backup")"
        if ! gunzip -c "$incre_backup" | btrfs receive "$temp_dir" 2>/dev/null; then
          echo "錯誤：增量備份應用失敗"
          return 1
        fi
      else
        echo "錯誤：在父備份目錄中找不到完整備份"
        return 1
      fi
    else
      echo "錯誤：增量備份需要父快照，但找不到適合的父備份"
      echo "建議："
      echo "1. 檢查是否有更早的完整備份"
      echo "2. 確保備份目錄結構正確"
      echo "3. 考慮從最新的完整備份開始還原"
      return 1
    fi
  else
    echo "錯誤：在 $backup_dir 中找不到備份檔案"
    echo "支援的備份檔案格式："
    echo "  - full.*.btrfs.gz (完整備份)"
    echo "  - incre.*.btrfs.gz (增量備份)"
    return 1
  fi
  
  # 查找還原後的 subvolume 並移動到目標位置
  # 對於增量備份，我們需要找到最新的 subvolume
  local restored_subvol
  if [ -n "$incre_backup" ]; then
    # 增量備份：找到最新的 subvolume（通常是最後修改的）
    restored_subvol=$(find "$temp_dir" -maxdepth 1 -type d -name "*snap*" | xargs -r ls -td | head -n 1)
  else
    # 完整備份：找到第一個 subvolume
    restored_subvol=$(find "$temp_dir" -maxdepth 1 -type d -name "*snap*" | head -n 1)
  fi
  
  if [ -n "$restored_subvol" ]; then
    echo "  設置 subvolume 為可寫"
    btrfs property set -fts "$restored_subvol" ro false || {
      echo "警告：無法設置 subvolume 為可寫，嘗試繼續"
    }
    
    echo "  移動還原的 subvolume 到目標位置"
    mv "$restored_subvol" "$target_path" || {
      echo "錯誤：無法移動還原的 subvolume"
      return 1
    }
  else
    echo "錯誤：找不到還原的 subvolume"
    echo "臨時目錄內容："
    ls -la "$temp_dir" || true
    return 1
  fi
  
  echo "  $description 還原完成"
  return 0
}

# 還原容器鏡像
restore_images() {
  echo "=================================================="
  echo "還原容器鏡像"
  echo "=================================================="
  
  if [ "$DRY_RUN" = true ]; then
    echo "  [預覽] 將從 Registry 拉取鏡像"
    grep "image:" "$METADATA" | while read -r line; do
      image_info=$(echo "$line" | cut -d':' -f2-)
      echo "    - $image_info"
    done
    return 0
  fi
  
  # 從 metadata 中讀取鏡像資訊並拉取
  grep "image:" "$METADATA" | while read -r line; do
    image_info=$(echo "$line" | cut -d':' -f2- | xargs)
    if [ -n "$image_info" ]; then
      echo "  拉取鏡像: $image_info"
      docker pull "$image_info" || {
        echo "警告：拉取鏡像 $image_info 失敗"
        continue
      }
      
      # 提取容器名稱和版本，創建本地標籤
      container_name=$(echo "$image_info" | cut -d'/' -f2 | cut -d':' -f1)
      version=$(echo "$image_info" | cut -d':' -f3)
      
      if [ -n "$container_name" ] && [ -n "$version" ]; then
        docker tag "$image_info" "${container_name}:latest" || {
          echo "警告：為鏡像 $image_info 創建標籤失敗"
        }
        echo "  鏡像 $container_name 還原完成"
      fi
    fi
  done
}

# 確認還原操作
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
  echo "警告：此操作將會覆蓋現有資料！"
  echo "專案將還原到: $NEW_PROJECT_PATH"
  echo "是否繼續？(y/N)"
  read -r confirmation
  if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
    echo "取消還原操作"
    exit 0
  fi
  echo ""
fi

# 如果要還原專案或 volumes，需要停止 Docker 服務
if [ "$RESTORE_PROJECT" = true ] || [ "$RESTORE_VOLUMES" = true ]; then
  # 檢查是否有 docker-compose.yaml 來停止服務（先檢查新位置，再檢查原位置）
  compose_file=""
  if [ -f "$NEW_PROJECT_PATH/docker-compose.yaml" ]; then
    compose_file="$NEW_PROJECT_PATH/docker-compose.yaml"
  elif [ -f "$ORIGINAL_PROJECT_PATH/docker-compose.yaml" ]; then
    compose_file="$ORIGINAL_PROJECT_PATH/docker-compose.yaml"
  fi
  
  if [ -n "$compose_file" ]; then
    echo "停止 Docker Compose 服務..."
    if [ "$DRY_RUN" = false ]; then
      compose_dir=$(dirname "$compose_file")
      cd "$compose_dir" || {
        echo "警告：無法進入專案目錄，跳過停止服務"
      }
      docker compose stop 2>/dev/null || echo "警告：停止服務失敗或無服務運行"
    else
      echo "  [預覽] 將停止 Docker Compose 服務"
    fi
  fi
fi

# 1. 還原專案資料夾
if [ "$RESTORE_PROJECT" = true ]; then
  echo "=================================================="
  echo "還原專案資料夾"
  echo "=================================================="
  
  restore_btrfs_backup "$PROJECT_BACKUP_DIR" "$NEW_PROJECT_PATH" "專案資料夾" "$RESTORE_SNAP_TMP" "project"
fi

# 2. 還原 Docker Volumes
if [ "$RESTORE_VOLUMES" = true ]; then
  echo "=================================================="
  echo "還原 Docker Volumes"
  echo "=================================================="
  
  if [ -d "$VOLUMES_BACKUP_DIR" ]; then
    for volume_backup_dir in "$VOLUMES_BACKUP_DIR"/*; do
      if [ -d "$volume_backup_dir" ]; then
        # 從目錄名提取 volume 名稱
        volume_name=$(basename "$volume_backup_dir")
        volume_path="$DOCKER_DIR/volumes/$volume_name/_data"
        
        restore_btrfs_backup "$volume_backup_dir" "$volume_path" "Volume $volume_name" "$DOCKER_RESTORE_TMP" "volumes/$volume_name"
      fi
    done
  else
    echo "警告：找不到 volumes 備份目錄"
  fi
fi

# 3. 還原 Bind Mounts
if [ "$RESTORE_BINDS" = true ]; then
  echo "=================================================="
  echo "還原 Bind Mounts"
  echo "=================================================="
  
  if [ -d "$BINDS_BACKUP_DIR" ]; then
    # 從 metadata 中讀取 bind mount 對應關係
    echo "正在分析 bind mount 對應關係..."
    
    for bind_backup_dir in "$BINDS_BACKUP_DIR"/*; do
      if [ -d "$bind_backup_dir" ]; then
        # 從目錄名提取編碼名稱
        encoded_name=$(basename "$bind_backup_dir")
        
        # 從 metadata 中查找對應的原始路徑
        original_path=$(grep "發現 bind mount:" "$METADATA" | grep " -> $encoded_name" | cut -d':' -f2 | cut -d' ' -f2)
        
        if [ -n "$original_path" ]; then
          restore_btrfs_backup "$bind_backup_dir" "$original_path" "Bind mount $original_path" "$RESTORE_SNAP_TMP" "binds/$encoded_name"
        else
          echo "警告：無法找到編碼名稱 $encoded_name 對應的原始路徑"
          if [ "$DRY_RUN" = false ]; then
            echo "可以嘗試手動解碼："
            echo "  編碼名稱: $encoded_name"
            echo "  解碼命令: echo '$encoded_name' | tr '_-' '/+' | base64 -d"
          fi
        fi
      fi
    done
  else
    echo "警告：找不到 binds 備份目錄"
  fi
fi

# 4. 還原容器鏡像
if [ "$RESTORE_IMAGES" = true ]; then
  restore_images
fi

# 重啟服務
if [ "$RESTORE_PROJECT" = true ] || [ "$RESTORE_VOLUMES" = true ]; then
  if [ -f "$NEW_PROJECT_PATH/docker-compose.yaml" ]; then
    echo "=================================================="
    echo "重新啟動 Docker Compose 服務"
    echo "=================================================="
    
    if [ "$DRY_RUN" = false ]; then
      cd "$NEW_PROJECT_PATH" || {
        echo "錯誤：無法進入專案目錄"
        exit 1
      }
      docker compose up -d || {
        echo "警告：重啟服務失敗，請手動檢查"
      }
    else
      echo "  [預覽] 將重新啟動 Docker Compose 服務"
    fi
  fi
fi

# 清理臨時目錄
if [ "$DRY_RUN" = false ]; then
  echo "清理臨時還原目錄..."
  rm -rf "$RESTORE_SNAP_TMP" 2>/dev/null || echo "清理臨時還原目錄失敗"
  rm -rf "$DOCKER_RESTORE_TMP" 2>/dev/null || echo "清理 Docker 臨時還原目錄失敗"
fi

echo "=================================================="
if [ "$DRY_RUN" = true ]; then
  echo "預覽完成！"
  echo "如要執行實際還原，請移除 --dry-run 選項"
else
  echo "還原完成！"
  echo ""
  echo "還原資訊："
  echo "  專案位置: $NEW_PROJECT_PATH"
  echo "  還原基礎目錄: $RESTORE_BASE_DIR"
  echo ""
  echo "注意事項："
  echo "1. 請檢查服務是否正常運行"
  echo "2. 如有問題，原始資料已備份為 *.backup_* 格式"
  echo "3. 詳細還原資訊請查看上述輸出"
  echo "4. 容器鏡像已從 Registry 拉取並重新標籤"
fi
echo "=================================================="

exit 0
