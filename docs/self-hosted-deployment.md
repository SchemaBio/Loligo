# SchemaBio 自部署说明

更新日期：2026-10-17。

SchemaBio 自部署版面向常见 Linux 服务器及集群环境。PostgreSQL 与 ZhiJi 用 Docker Compose 运行。Loligo 是宿主机服务 `zhiji-loligo`，监听 `LOLIGO_PORT`（默认 8082），不是 Compose 服务。生产安装入口是 `deploy/deploy.sh`。

按以下步骤准备环境、保存配置、启动服务并下载参考数据库。

## 1. 组件与交付方式

| 组件 | 用途 | 镜像地址 |
| --- | --- | --- |
| ZhiJi | 平台前端 | `docker.schema-bio.com/schemabio/zhiji:latest` |
| Loligo | 账户、业务 API、任务与结果管理 | 宿主机 systemd 服务 `zhiji-loligo`，不由 Compose 启动 |
| Sepiida Server | 外部共享的工作流状态服务，不由本仓库安装 | 使用已有服务的 `SEPIIDA_URL` |
| PostgreSQL | 平台结构化数据 | `postgres:16-alpine` |

ZhiJi 以预构建 Docker 镜像提供，发布到 `docker.schema-bio.com/schemabio`，由 Compose 启动。Loligo 不作为该 Compose 的服务运行。`deploy/deploy.sh install` 从应用镜像抽出二进制放到宿主机，再由 systemd 单元 `zhiji-loligo` 启动。Sepiida Server 不在本 Compose 中拉取或启动。

ZhiJi 使用 `latest` 标签；PostgreSQL 使用 `postgres:16-alpine`。镜像发布后，配合对应的 Compose、配置示例及数据库升级说明使用。

分析步骤镜像也位于该镜像仓库。平台前端镜像和分析工具镜像用途不同，分析所需镜像列于下方。

服务器需要安装 Docker 和 MiniWDL。Docker Compose 只启动 PostgreSQL 与 ZhiJi。MiniWDL 安装在宿主机上，供 `zhiji-loligo` 执行分析流程。Sepiida Server 与 Sepiida Agent 由现有外部共享服务提供，本仓库不安装、不构建、不重启它们。需要 Agent 的工作流必须指向已经在运行的外部 Agent。



## 2. 环境准备

在 Linux 服务器上安装以下组件：

- **Docker**：包含 Docker Compose，用于启动平台服务和分析容器。
- **MiniWDL**：用于执行 WDL 分析流程。
- **外部 Sepiida Agent**：不在本仓库安装。需要状态上报时，使用已经由共享 Sepiida 管理的 Agent。

安装后检查 Docker 和 MiniWDL。不要在本仓库的安装步骤中启动 Sepiida Agent：

```bash
docker version
docker compose version
miniwdl --version
```

按分析流程和并发量准备足够的 CPU、内存及磁盘空间。集群中的执行节点也需配置对应运行环境和数据访问路径。

### 准备 schema-germline 分析镜像

运行 schema-germline 前，在分析执行节点拉取以下镜像。分析工具保留工作流指定的版本标签，平台应用使用的 `latest` 标签不适用于此清单。

```text
docker.schema-bio.com/schemabio/germline:v0.1.7
docker.schema-bio.com/schemabio/mapping:v1.1.0
docker.schema-bio.com/schemabio/automap:1.3
docker.schema-bio.com/schemabio/cnvanno:v0.0.2
docker.schema-bio.com/schemabio/cnvkit:0.9.13.2
docker.schema-bio.com/schemabio/deeptrio:1.10.0
docker.schema-bio.com/schemabio/deepvariant:1.10.0
docker.schema-bio.com/schemabio/expansionhunter:5.0.0
docker.schema-bio.com/schemabio/gatk:4.6.2.0
docker.schema-bio.com/schemabio/glnexus:v1.4.1
docker.schema-bio.com/schemabio/peddy:0.4.8
docker.schema-bio.com/schemabio/stranger:v0.10.0.1
docker.schema-bio.com/schemabio/tiea_wes:2.0.1
docker.schema-bio.com/schemabio/vep:116.0
docker.schema-bio.com/schemabio/whatshap:2.8
```

上述清单覆盖当前 schema-germline 任务文件及默认运行配置引用的镜像。升级工作流时同步核对镜像版本。集群部署需保证每个承担分析的节点均可获取这些镜像；`docker compose pull` 只拉取 Compose 中声明的平台服务镜像，不会自动准备上述分析镜像。

## 3. 建立持久化目录

部署根目录由部署者选择，例如 `/mnt/data`。集群可使用所有相关执行节点可访问的共享存储目录。

```text
/mnt/data/
  deploy/            Compose、环境变量及服务配置
  database/          参考基因组和注释库
  uploads/           测序输入及上传文件
  output/            分析运行目录
  archive/           归档目录
  cache/             分析与查询缓存
  schema-germline/   工作流及执行配置
  docs/              部署与维护记录
```

`database/` 在这里指生信参考库。PostgreSQL 数据需另行持久化到命名卷、独立目录或受管理的数据库服务，按部署需求选择，不能与参考库混淆。

文件配置使用容器内部的 Linux 绝对路径。对于需要由 Loligo 通过 Docker 创建分析容器的执行方式，应保证 Loligo、执行节点和分析容器可按配置读取同一份输入、参考库及输出目录；采用一致的绝对挂载路径可减少路径转换问题。

## 4. 完整 Compose 与环境变量配置

所有参数值集中在 `.env` 中；Compose 仅列出各服务需要的变量名，避免把数据库密码或 JWT 密钥传给前端。

将以下配置文件保存到 `/mnt/data/deploy`，MiniWDL 配置保存到 `/mnt/data/schema-germline/conf/local.cfg`。所有文件使用 Linux LF 换行。本例使用单机 Docker 执行器，默认端口仅监听本机。Compose 只包含 PostgreSQL 和 ZhiJi。

Loligo 是宿主机进程，MiniWDL 也装在宿主机上，默认路径为 `/opt/miniwdl/bin/miniwdl`。ZhiJi 容器通过 `host.docker.internal` 访问这个宿主机端口。`extra_hosts` 将 `host.docker.internal` 映射为 `host-gateway`。不要使用不存在的 Compose 主机名 `loligo`。

### 4.1 compose.yaml

保存为 `/mnt/data/deploy/compose.yaml`。

```yaml
name: zhiji-loligo

services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment: [POSTGRES_USER, POSTGRES_DB, POSTGRES_PASSWORD, LOLIGO_DB_PASSWORD]
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-databases.sh:/docker-entrypoint-initdb.d/10-init-databases.sh:ro
      - ./init-databases.sql:/docker-entrypoint-initdb.d/10-init-databases.sql.template:ro
    ports:
      - '${BIND_ADDRESS}:${POSTGRES_PORT:-54322}:5432'
    healthcheck:
      test: [CMD-SHELL, 'pg_isready -U postgres -d postgres']
      interval: 5s
      timeout: 5s
      retries: 30

  zhiji:
    image: docker.schema-bio.com/schemabio/zhiji:latest
    restart: unless-stopped
    environment:
      TZ: Asia/Shanghai
      ZHIJI_API_URL: /api
      ZHIJI_SERVER_API_URL: http://host.docker.internal:${LOLIGO_PORT:-8082}/api
      ZHIJI_BACKEND: loligo
      ZHIJI_DEFAULT_LOCALE: ${ZHIJI_DEFAULT_LOCALE:-zh-CN}
    extra_hosts:
      - host.docker.internal:host-gateway
    ports:
      - '${BIND_ADDRESS}:${ZHIJI_PORT:-3002}:3000'

volumes:
  postgres-data:
```

### 4.2 .env

保存为 `/mnt/data/deploy/.env`。数据库密码和 JWT 密钥用 openssl 生成。Sepiida 的地址和 Query Key 只填写现有共享服务提供的值，留空则保持关闭。

```dotenv
# 以下三项分别使用 openssl rand -hex 32 生成。
POSTGRES_PASSWORD=
LOLIGO_DB_PASSWORD=
JWT_SECRET=
DEFAULT_ADMIN_EMAIL=admin@example.org
DEFAULT_ADMIN_PASSWORD=

# 服务地址与端口：默认本机 HTTP。
TZ=Asia/Shanghai
BIND_ADDRESS=127.0.0.1
ZHIJI_PORT=3002
LOLIGO_PORT=8082
POSTGRES_PORT=54322
# Browser contract: same-origin /api. The reverse proxy forwards /api to the host listener.
ZHIJI_API_URL=/api
# ZhiJi container to host zhiji-loligo. Keep the port equal to LOLIGO_PORT.
ZHIJI_SERVER_API_URL=http://host.docker.internal:8082/api
ZHIJI_BACKEND=loligo
ZHIJI_DEFAULT_LOCALE=zh-CN

# Loligo 自部署配置。
DEPLOYMENT_EDITION=opensource
SERVER_PORT=8082
GIN_MODE=debug
ALLOW_INSECURE_DEV=true
CORS_ALLOWED_ORIGINS=http://localhost:3002,http://127.0.0.1:3002
JWT_COOKIE_SECURE=false
CREATE_DEFAULT_ADMIN=true
EXTERNAL_AUTH_ENABLED=false
OVERLAY_ENABLED=false

# 数据库：密码只填写上面的项，连接配置自动引用。
POSTGRES_USER=postgres
POSTGRES_DB=postgres
DB_DSN="host=127.0.0.1 user=loligo password=${LOLIGO_DB_PASSWORD} dbname=loligo port=${POSTGRES_PORT} sslmode=disable TimeZone=Asia/Shanghai"

# 宿主机与容器采用一致绝对路径。
SCHEMABIO_ROOT=/mnt/data
STORAGE_PROVIDER=local
STORAGE_LOCAL_DIR=${SCHEMABIO_ROOT}/uploads
OUTPUT_DIR=${SCHEMABIO_ROOT}/output
ARCHIVE_DIR=${SCHEMABIO_ROOT}/archive
TEMPLATE_DIR=${SCHEMABIO_ROOT}/schema-germline
DEFAULT_EXECUTOR=local
# 宿主机路径。zhiji-loligo 在宿主机调用 MiniWDL。
MINIWDL_PATH=/opt/miniwdl/bin/miniwdl
MINIWDL_SLURM_PATH=/opt/miniwdl/bin/miniwdl
MINIWDL_LSF_PATH=/opt/miniwdl/bin/miniwdl
MINIWDL__FILE_IO__ROOT=${SCHEMABIO_ROOT}
MINIWDL__CALL_CACHE__DIR=${SCHEMABIO_ROOT}/cache
MINIWDL__DOCKER_SWARM__AUTO_INIT=true
PARQUET_ENABLED=true
PARQUET_CACHE_DIR=${SCHEMABIO_ROOT}/cache/parquet

# IGV 使用的容器内参考序列路径；对应的 .fai 文件放在 FASTA 旁边。
IGV_HG19_FASTA_PATH=${SCHEMABIO_ROOT}/database/Homo_sapiens.GRCh37.dna.primary_assembly.fa
IGV_HG38_FASTA_PATH=${SCHEMABIO_ROOT}/database/Homo_sapiens.GRCh38.dna.primary_assembly.fa

# Sepiida is an existing external shared service. Do not start a server or agent here.
# Copy SEPIIDA_QUERY_KEY from that service. Do not generate one.
SEPIIDA_ENABLED=false
SEPIIDA_URL=
SEPIIDA_QUERY_KEY=
```

### 4.3 数据库初始化脚本

保存为 `/mnt/data/deploy/init-databases.sh`。

```sh
#!/bin/sh
set -eu
psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=loligo_password="$LOLIGO_DB_PASSWORD" \
  --file=/docker-entrypoint-initdb.d/10-init-databases.sql.template
```

### 4.4 数据库初始化 SQL

保存为 `/mnt/data/deploy/init-databases.sql`。

```sql
SELECT format('CREATE ROLE loligo LOGIN PASSWORD %L', :'loligo_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'loligo') \gexec
SELECT 'CREATE DATABASE loligo OWNER loligo'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'loligo') \gexec
```

### 4.5 MiniWDL 配置

按服务器类型选择一种配置。单机使用 `local.cfg`，Slurm 使用 `slurm.cfg`，LSF 使用 `lsf.cfg`，均保存到 `/mnt/data/schema-germline/conf/`。`/mnt/data` 在集群中应为提交端与计算节点都能访问的共享路径。

#### 单机 Docker

`.env` 使用：

```dotenv
DEFAULT_EXECUTOR=local
MINIWDL_PATH=/opt/miniwdl/bin/miniwdl
```

`local.cfg`：
```ini
[scheduler]
container_backend = docker_swarm
task_concurrency = 16

[task_runtime]
defaults = {
    "docker": "docker.schema-bio.com/schemabio/germline:v0.1.7",
    "cpu": 4,
    "memory": "8G"
    }
as_user = true

[file_io]
root = /mnt/data

[call_cache]
get = true
put = true
dir = /mnt/data/cache
```

#### Slurm 集群

在运行 MiniWDL 的 Python 环境中安装插件：

```bash
python -m pip install miniwdl-slurm
```

`.env` 改为：

```dotenv
DEFAULT_EXECUTOR=slurm
MINIWDL_SLURM_PATH=/opt/miniwdl/bin/miniwdl
```

`slurm.cfg` 如下，将 `compute` 和 `my_account` 替换为实际分区、账户，不需要账户参数时删去 `--account`：
```ini
[scheduler]
container_backend = slurm_singularity
task_concurrency = 16

[task_runtime]
defaults = {
    "docker": "docker.schema-bio.com/schemabio/germline:v0.1.7",
    "cpu": 4,
    "memory": "8G"
    }

[file_io]
root = /mnt/data

[call_cache]
get = true
put = true
dir = /mnt/data/cache

[singularity]
exe = ["singularity"]
run_options = ["--containall", "--no-mount", "hostfs"]
image_cache = /mnt/data/cache/singularity

[slurm]
extra_args = --partition=compute --account=my_account
```

#### LSF 集群

在运行 MiniWDL 的 Python 环境中安装插件：

```bash
python -m pip install miniwdl-lsf
```

`.env` 改为：

```dotenv
DEFAULT_EXECUTOR=lsf
MINIWDL_LSF_PATH=/opt/miniwdl/bin/miniwdl
```

`lsf.cfg` 如下，将 `normal` 和 `my_project` 替换为实际队列、项目，不需要项目参数时删去 `-P my_project`：
```ini
[scheduler]
container_backend = lsf_singularity
task_concurrency = 16

[task_runtime]
defaults = {
    "docker": "docker.schema-bio.com/schemabio/germline:v0.1.7",
    "cpu": 4,
    "memory": "8G"
    }

[file_io]
root = /mnt/data

[call_cache]
get = true
put = true
dir = /mnt/data/cache

[singularity]
exe = ["singularity"]
run_options = ["--containall", "--cleanenv"]
image_cache = /mnt/data/cache/singularity

[lsf]
extra_args = -q normal -P my_project
memory_per_job = true
```

#### 集群运行条件

Slurm/LSF 使用上述插件时，运行命令仍是 `miniwdl`，不是 `miniwdl-slurm` 或 `miniwdl-lsf`。如安装位置不同，将 `.env` 中对应路径改为实际的 MiniWDL 可执行文件。

宿主机服务 `zhiji-loligo` 在宿主机启动 MiniWDL，因此插件、Slurm 的 `sbatch/squeue/scancel` 或 LSF 的 `bsub/bjobs/bkill`、Singularity 及集群认证配置必须在该宿主机用户的环境里可用。使用集群管理员提供的提交环境，并以具备提交权限的集群用户运行。

集群节点需能访问工作目录、参考库和镜像缓存。集群使用 Apptainer 时，将 `exe = ["singularity"]` 改为 `exe = ["apptainer"]`。

配置文件使用上面给出的插件字段：`[scheduler] container_backend` 和 `[slurm]`/`[lsf] extra_args`。若工作流仓库自带配置不同，按本文内容替换。配置依据：[Slurm 插件](https://github.com/miniwdl-ext/miniwdl-slurm)、[LSF 插件](https://github.com/adthrasher/miniwdl-lsf)。

### 4.6 外部 Sepiida Agent

本仓库不安装、不生成、不启动 Sepiida Agent，也不编写 Agent 密钥或 systemd 单元。需要采集任务状态时，使用已经由外部共享 Sepiida 管理的 Agent，让它监视本部署的输出目录（示例为 `/mnt/data/output`）。Agent 自己的密钥留在外部服务，不要在这里新生成。

## 5. 部署步骤

### 5.1 准备目录和工作流

```bash
sudo mkdir -p /mnt/data/{deploy,database,uploads,output,archive,cache}
git clone https://github.com/SchemaBio/schema-germline.git /mnt/data/schema-germline
cd /mnt/data/deploy
chmod 600 .env
```

先按第 4 节保存所有配置文件，再执行以上操作。目录应允许平台及 Agent 运行用户读写。工作流仓库已存在时使用已有目录，不要覆盖本机配置。按本文的镜像清单及数据库配置章节准备分析资源。

示例统一使用 `/mnt/data`，与内置流程的默认参考库根目录一致。如果修改 `SCHEMABIO_ROOT`，还需同步调整 MiniWDL 配置、Agent 配置及流程参数中的参考库绝对路径。宿主机、Loligo 和分析容器保持相同路径映射。

### 5.2 填写环境变量

编辑 `.env`，填写所有空值。为以下每项分别运行 `openssl rand -hex 32` 生成独立随机值：

- `POSTGRES_PASSWORD`
- `LOLIGO_DB_PASSWORD`
- `JWT_SECRET`

`DEFAULT_ADMIN_EMAIL` 填写管理员邮箱，`DEFAULT_ADMIN_PASSWORD` 填写独立强密码。`SEPIIDA_QUERY_KEY` 从现有共享 Sepiida 复制，不要在这里用 openssl 新生成 Sepiida 密钥或数据库密码。密码可使用 `Aa1` 加随机十六进制字符串。使用十六进制数据库密码可以避免连接 URL 和 DSN 的特殊字符转义问题。

默认配置只监听 `127.0.0.1`，适合通过服务器本机或 SSH 端口转发访问：

```bash
ssh -L 3002:127.0.0.1:3002 -L 8082:127.0.0.1:8082 user@server
```

随后在客户端访问 `http://localhost:3002`。默认 HTTP 配置使用 debug 模式及非 Secure Cookie。

对外提供服务时使用 HTTPS 反向代理，并同步设置：

```dotenv
GIN_MODE=release
ALLOW_INSECURE_DEV=false
JWT_COOKIE_SECURE=true
ZHIJI_API_URL=/api
CORS_ALLOWED_ORIGINS=https://app.example.org
```

域名换成实际地址。反向代理把 `/api/*` 原样转到宿主机 Loligo `127.0.0.1:8082`（或 `LOLIGO_PORT`），其他应用路径转到 `127.0.0.1:3002`。浏览器继续使用 `/api`。不要把 `ZHIJI_API_URL` 写成 `http://host.docker.internal:...` 或 `http://loligo:8080/api`。ZhiJi 容器访问宿主机的内部地址是 `ZHIJI_SERVER_API_URL=http://host.docker.internal:${LOLIGO_PORT:-8082}/api`，由 `extra_hosts` 的 `host.docker.internal:host-gateway` 提供。本 Compose 没有 Loligo 容器。API 和前端应使用可满足浏览器 Cookie 策略的站点部署方式。反向代理在宿主机时可继续保留本机端口绑定。

### 5.3 连接外部 Sepiida

不要创建 Sepiida 数据库、密钥文件或本地 Sepiida Server。在 `.env` 中把 `SEPIIDA_ENABLED` 设为 `true` 时，`SEPIIDA_URL` 与 `SEPIIDA_QUERY_KEY` 必须填写现有共享服务提供的值。留空并保持 `SEPIIDA_ENABLED=false` 时，Loligo 可以单独启动，但不会查询工作流进度。需要 Agent 的流程指向已经在外部管理的 Agent，不要在本机安装一个。

### 5.4 启动平台服务

```bash
cd /mnt/data/deploy
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 180
docker compose ps
```

Compose 只启动 PostgreSQL 和 ZhiJi。PostgreSQL 发布到 `127.0.0.1:${POSTGRES_PORT:-54322}`，供宿主机上的 `zhiji-loligo` 连接。ZhiJi 留在 Compose 网络中，通过 `host.docker.internal` 调用宿主机 `LOLIGO_PORT`。`docker compose ps` 里没有 Loligo 服务。数据库保存在 `zhiji-loligo_postgres-data` 命名卷；`/mnt/data/database` 是生信参考库。

初始化 SQL 只在空 PostgreSQL 数据卷首次启动时执行。已有数据库的密码不会因修改 `.env` 自动改变，应通过数据库管理操作同步修改。Sepiida 的 URL 和 Query Key 来自已经存在的共享服务，不在这里生成，也不要为本仓库新建 Sepiida 数据库或密钥。

本机执行器由宿主机上的 `zhiji-loligo` 通过 Docker 启动分析容器。该服务用户需要属于 Docker 组。本 Compose 不把 Docker socket 挂给 ZhiJi，也不运行 Loligo 容器。集群调度方式需要对应的执行器配置，不能只修改目录就视为集群部署完成。

### 5.5 外部 Agent

不要从本仓库安装或启动 Agent。若工作流需要状态上报，确认外部 Agent 已在运行，并且它的服务地址与 Query Key 属于同一个共享 Sepiida，而不是本部署新生成的密钥。

### 5.6 验证服务

```bash
cd /mnt/data/deploy
curl -fsS http://127.0.0.1:8082/health
miniwdl --version
```

健康检查打在宿主机 Loligo 端口上，不是容器内的 8080，也不是 `docker compose exec`。MiniWDL 在宿主机上检查。确认前端可登录即可。Agent 上报由外部共享 Sepiida 负责，不在本仓库启动。

更新平台镜像：

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 180
```

升级前备份数据库、配置和重要业务数据，按发布说明处理迁移，并评估正在运行的任务。日常停止使用 `docker compose stop`；不要执行 `docker compose down -v` 删除持久化卷。



## 6. 下载参考数据库

从 [Hugging Face：SchemaBio_Bundle](https://huggingface.co/datasets/pzweuj/SchemaBio_Bundle) 下载所需的 hg19 或 hg38 数据。

将对应版本的参考基因组文件放到 `/mnt/data/database`，注释文件放到 `/mnt/data/database/schema_bundle`，并将 VEP cache 解压到 `/mnt/data/database/vep`。

以 hg19 为例，在 `/mnt/data/database` 中执行：

```bash
cd /mnt/data/database
gzip -dk Homo_sapiens.GRCh37.dna.primary_assembly.fa.gz
mkdir -p vep
tar -xzf homo_sapiens_merged_vep_116_GRCh37.tar.gz -C vep
```

hg38 对应使用 `GRCh38` 的参考基因组和 VEP cache 文件。

## VCF 注释流程升级

VCF2Anno 使用单一 vcf2anno.wdl，由 Loligo 配置 hg19/hg38 参考资源。执行端工作流包及 germline 镜像必须包含新增初始化、性别推算脚本和更新的报表脚本，固定调用 /opt/schema-germline/scripts/。升级时先准备执行环境，再更新 Onykia（SaaS）、Loligo 和两个前端；Loligo 自动迁移性别阈值字段。具体参数与回归要求见 [VCF2Anno 接入说明](vcf2anno-integration.md)。

## SepiLens v2 AI 证据整理

ZhiJi 的个人设置中可配置模型地址、协议、名称和 API Key。Loligo 设置 AI_ASSISTANCE_BASE_URL 指向 SepiLens 内网服务，AI_ASSISTANCE_TOKEN 与 SepiLens 的服务身份密钥一致；AI_ASSISTANCE_MASTER_KEY 使用独立的 base64 32 字节随机密钥，保护已保存的模型配置。独立容器部署时 AI_ASSISTANCE_MANAGED_PROCESS=false。

SepiLens 设置 SEPILENS_AI_MODE=enabled、SEPILENS_AI_ONLY=true，使用独立加密业务存储。默认要求规则签名；仅用于 AI 证据整理时，可显式设置 SEPILENS_REQUIRE_RULE_APPROVAL=false，未批准结果保持 evidence_only，不启用正式医学规则。此集成固定提交 v2 ai_assisted，拒绝本地评估，AI 失败不会回退为本地基线。HPO AI 提取调用 POST /v2/hpo/extract；原文仅在当前请求内存中保留，结束后清理，失败不回退到本地提取。不要把模型 Key 放入前端环境变量。
