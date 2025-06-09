# docker-bakeup tools

目前在網路上有針對 container 的備份工具，也有針對整個 VM 或是系統的備份工具，但鮮少看到有針對 Docker Compose 的備份工具，故此工具是一個針對 Docker Compose 專案的備份還原工具，專為使用 Btrfs 檔案系統的環境設計。此工具可自動備份整個專案結構、Volumes 與 Bind Mounts，並能輕鬆還原至指定狀態，希望能在特定情況幫助到別人。
## 系統需求
- OS 需為 Linux
- 檔案系統需為 **Btrfs**。
    - 或是需備份的資料夾所在為 **Btrfs** (docker 所在資料夾、專案所在資料夾、volumes 所在資料夾)
    - 將 docker 資料夾做成 btrfs 可參考 [BTRFS storage driver](https://docs.docker.com/engine/storage/drivers/btrfs-driver/)
- 需有 docker
  - 安裝可參考 [1132 LSA-II 虛擬化(一) 講義](https://hackmd.io/@k7pRcwifQeipyTOGHpk1vg/SyqBlJnnyg) Docker 架構部分的安裝步驟
- 被備份的 Docker Compose 專案需儲存在以下路徑：
  - `/home/<username>/project/<your project dir>/`
- 會需要 **docker registry** 來達成 image 的增量備份

## 備份結構說明

備份資料將儲存在 `/home/<username>/backup/docker/` 下，以專案名稱命名的資料夾中，每次備份會以 timestamp 為子資料夾名稱。

```
/home/<username>/backup/docker/
└── <project name>/
    └── <timestamp>/
        ├── docker-compose.yaml        # 專案的 compose 檔案
        ├── metadata.txt               # 備份過程記錄（如時間、成功與否、相關訊息）
        ├── project/                   # 專案完整內容
        ├── binds/                     # 非專案目錄內的 bind mount 內容（base64 編碼目錄名）
        └── volumes/                   # 使用到的 volumes（以 volume 名為目錄名）
```

* `binds/`：僅包含非專案目錄下的 bind mounts。其資料夾名稱為原始路徑的 base64 編碼。
* `volumes/`：以 volume 名稱為資料夾名，包含 volume 的完整內容。

## 使用方式
### 安裝
執行以下指令進行安裝
```bash
wget https://raw.githubusercontent.com/dreamaker0224/docker-bakeup/main/docker-bakeup-package.tar.gz
tar xzvf docker-bakeup-package.tar.gz
cd docker-bakeup-package
chmod +x install.sh
sudo ./install.sh
```
### 備份
請先啟動 docker registry：
```bash
docker run -d -p 5000:5000 --restart always --name registry registry:2
```
此步驟會啟用一個由 docker 官方提供的 registry v2
- registry 是一個集中管理 Docker 映像的系統，例如：Docker Hub、ECR、GCR。
- 很像 github，可以 `pull`、`push` 與 registry 互動
- 能使用 tag 進行版本管理
- image layer 本身具有增量的特性

此工具應其 tag 功能以及增量特性，作為 image 備份管理的主要媒介

備份專案時執行以下指令 (project path 底下需要包含 docker-compose.yaml)：

```bash
sudo docker-bakeup backup <project path>
```

此指令會自動：
- 偵測專案名稱
- 備份專案檔案、bind mounts、以及 volumes
- 儲存至 `/home/<username>/backup/docker/<project name>/<timestamp>/`

### 還原

執行以下指令並指定要還原的備份資料夾（timestamp 資料夾，請輸入絕對路徑）到指定的資料夾底下，未指定則為當前資料夾：

```bash
sudo docker-bakeup restore <backup path timestamp> <restore path>
```
範例：
以下指令即會復原到 home 目錄下 Downloads 資料夾底下
```bash
sudo docker-bakeup restore /home/justin/backup/docker/myprojet/20250609_190334 ./Downloads
```
還原會還原以下：
- 整個專案資料夾，包括 docker-compose.yaml
- volumes 
- bind mounts (若位置非 btrfs 則無法還原，需手動操作)
- image
    - image 會從 registry pull 下來，並重新 tag 為 docker-compose 的 image 內容


接著即可使用 `docker compose up` 重新啟動服務


## docker-bakeup for dr-site demo
共同合作的專題為 [LSA2_CSF_POC
](https://github.com/Hikana/LSA2_CSF_POC)，為 POC 提供備份還原及，dr-site 同步的解決方案
### simple structure
![image](https://hackmd.io/_uploads/BykDcykQge.png)
### 安裝 docker-bakeup
在兩邊的 site 都安裝 docker-bakeup
執行以下指令進行安裝
```bash
wget https://raw.githubusercontent.com/dreamaker0224/docker-bakeup/main/docker-bakeup-package.tar.gz
tar xzvf docker-bakeup-package.tar.gz
cd docker-bakeup-package
chmod +x install.sh
sudo ./install.sh
```
### registry sync
在 primal site 下載 registry_sync.sh
```bash
wget https://raw.githubusercontent.com/dreamaker0224/docker-bakeup/main/dr-stie-poc/registry_sync.sh
```

若無 https 則於 primal site 編輯 `/etc/docker/daemon.json`，在裡面加入：
```bash
{
  "insecure-registries":["<drsite-ip>:5000"]
}
```
### 傳輸備份檔
將以下兩行加入 crontab，即可實現定期同步備份檔
```bash
sudo /home/primal/registry_sync.sh
rsync -av /home/primal/backup/* drsite@<drsite ip>:/home/drsite/backup/
```
### DNS 接管
1. 使用 ngrok 將內網映射到公用 IP
`ngrok http 8080`
![image](https://github.com/user-attachments/assets/baf36ae8-c3e4-4345-9765-7427c4c4c50d)


2. DNS_SERVER 接收來自 DRSITE 發送的訊號(一個檔案)

```bash
#!/bin/bash

MAIN_HOST="10.107.13.83"
DR_HOST="10.107.47.110"
SERVICE_PORT=8080
DNS_FLAG_FILE="/home/dnsserver/dns_request"
TUNNEL_PORT=$SERVICE_PORT

# 檢查是否已有現有 SSH Tunnel
check_existing_tunnel() {
    lsof -i TCP:$TUNNEL_PORT | grep ssh >/dev/null
}

# 清除現有的 SSH Tunnel
kill_existing_tunnel() {
    pkill -f "ssh -L $SERVICE_PORT"
}

# 使用 curl 檢查某個主機:PORT 是否可連
check_curl() {
    local HOST=$1
    curl --silent --max-time 3 http://$HOST:$SERVICE_PORT >/dev/null
    return $?
}

# 若 tunnel 存在則先清除
if check_existing_tunnel; then
    echo "移除現有的 SSH Tunnel..."
    kill_existing_tunnel
fi

# 嘗試連接主站
if check_curl $MAIN_HOST; then
    echo "主站可連線，建立 MAIN_HOST tunnel"
    ssh -L $SERVICE_PORT:$MAIN_HOST:$SERVICE_PORT -N -f primal@$MAIN_HOST
    [ -f "$DNS_FLAG_FILE" ] && rm -f "$DNS_FLAG_FILE"
else
    if [ ! -f "$DNS_FLAG_FILE" ]; then
        echo "主站無回應，檢查備援站..."
        if check_curl $DR_HOST; then
            echo "備援站可用，建立 DR_HOST tunnel"
            ssh -L $SERVICE_PORT:$DR_HOST:$SERVICE_PORT -N -f drsite@$DR_HOST
            touch "$DNS_FLAG_FILE"
        else
            echo "主站與備援站皆無回應，不執行任何 tunnel"
        fi
    else
        echo "已經在備援狀態，主站仍不可用，不切換"
    fi
fi

```


## References
[1132 LSA-II 虛擬化(一) 講義](https://hackmd.io/@k7pRcwifQeipyTOGHpk1vg/SyqBlJnnyg)
[What is a registry?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/)
[Distribution Registry](https://hub.docker.com/_/registry)
[BTRFS storage driver](https://docs.docker.com/engine/storage/drivers/btrfs-driver/)
[LSA2_CSF_POC
](https://github.com/Hikana/LSA2_CSF_POC)

