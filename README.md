# docker-bakeup tools

這是一個針對 Docker Compose 專案的備份還原工具，專為使用 Btrfs 檔案系統的環境設計。此工具可自動備份整個專案結構、Volumes 與 Bind Mounts，並能輕鬆還原至指定狀態。

## 系統需求

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

請在 Docker Compose 專案目錄下執行以下指令：

```bash
sudo ./backup.sh
```

此指令會自動：

* 偵測專案名稱
* 匯出 `docker-compose.yaml`
* 備份專案檔案、bind mounts、以及 volumes
* 儲存至 `/home/<username>/backup/docker/<project name>/<timestamp>/`

### 還原

執行以下指令並指定要還原的備份資料夾（timestamp 資料夾）：

```bash
sudo ./restore.sh /home/<username>/backup/docker/<project name>/<timestamp>
```

還原後會將資料放置於：

```
/home/<username>/project/<project name>/
```

接著即可啟動服務：

```bash
cd /home/<username>/project/<project name>/
```


- **simple structure**
![image](https://hackmd.io/_uploads/BykDcykQge.png)



## References
[1132 LSA-II 虛擬化(一) 講義](https://hackmd.io/@k7pRcwifQeipyTOGHpk1vg/SyqBlJnnyg)
[What is a registry?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/)
[Distribution Registry](https://hub.docker.com/_/registry)
