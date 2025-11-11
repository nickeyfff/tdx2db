# tdx2db - 简单可靠的 A 股行情数据库

[TOC]

## 概述

`tdx2db` 可以将通达信数据导入到 DuckDB 中。

使用 DuckDB 中数据的代码示例见: [ko_trading](https://github.com/jing2uo/ko_trading)

## 亮点

- **快速运行**：Go 语言实现，全量导入不到 6s
- **增量更新**：支持增量更新数据
- **分时数据**：增量更新时可选导入 1min 和 5min 分时数据
- **复权计算**：增量更新时会自动计算前后复权因子和行情
- **换手率和市值**：视图 v_turnover 存放了换手率和市值信息
- **使用通达信数据**：稳定可靠，不用买积分或被限流
- **单文件无依赖**：程序和数据库都只有一个文件

## 安装说明

### 使用 Docker 或 podman

项目会利用 github action 构建容器镜像，windows 和 mac 可以通过 docker 或 podman 使用:

```bash
docker run --rm --platform=linux/amd64 ghcr.io/jing2uo/tdx2db:latest -h
```

### 支持 Python 脚本的 Docker 镜像

最新版本的 Docker 镜像集成了 [ko_trading](https://github.com/jing2uo/ko_trading) 子工程，支持在容器中运行 Python 数据处理脚本：

```bash
# 更新中证指数成分股数据
docker run --rm --platform=linux/amd64 \
  -v "$(pwd)":/data \
  ghcr.io/jing2uo/tdx2db:latest \
  run_csindex_update

# 更新申万行业分类数据
docker run --rm --platform=linux/amd64 \
  -v "$(pwd)":/data \
  ghcr.io/jing2uo/tdx2db:latest \
  run_shenwan_industry_update

# 查看所有支持的命令
docker run --rm --platform=linux/amd64 ghcr.io/jing2uo/tdx2db:latest help
```

镜像特性：
- 集成了 Python 3.12 和 uv 包管理器
- 预装了 ta-lib、duckdb、vectorbt 等量化分析依赖
- 包含完整的 ko_trading 代码库
- 支持参数化入口，统一调用 tdx2db 和 Python 脚本

### 二进制安装

从 [releases](https://github.com/jing2uo/tdx2db/releases) 下载对应系统的二进制文件，解压后移至 `$PATH`，二进制仅支持在 Linux 中直接使用，Windows 建议开启 wsl ：

```bash
sudo mv tdx2db /usr/local/bin/
tdx2db -h # 验证安装
```

## 使用方法

### 初始化

首次使用必须先全量导入历史数据，可以从 [通达信券商数据](https://www.tdx.com.cn/article/vipdata.html) 下载**沪深京日线数据完整包**使用。

Linux 或 mac ：

```shell
mkdir vipdoc
wget https://data.tdx.com.cn/vipdoc/hsjday.zip && unzip -q hsjday.zip -d vipdoc

# docker
docker run --rm --platform=linux/amd64 \
  -v "$(pwd)":/data \
  ghcr.io/jing2uo/tdx2db:latest \
  init --dayfiledir /data/vipdoc --dbpath /data/tdx.db

# Linux 二进制
tdx2db init --dayfiledir vipdoc --dbpath tdx.db
```

Windows powershell ：

```shell
# 下载文件
Invoke-WebRequest -Uri "https://data.tdx.com.cn/vipdoc/hsjday.zip" -OutFile "hsjday.zip"
# 解压文件
Expand-Archive -Path "hsjday.zip" -DestinationPath "vipdoc" -Force
# 执行 init
docker run --rm --platform=linux/amd64 \
  -v "${PWD}:/data" \
  ghcr.io/jing2uo/tdx2db:latest \
  init --dayfiledir /data/vipdoc --dbpath /data/tdx.db
```

示例输出:

```shell
🛠 开始转换 dayfiles 为 CSV
🔥 转换完成
📊 股票数据导入成功
✅ 处理完成，耗时 5.007506252s
```

运行结束后 tdx.db 会在当前工作目录，和 vipdoc 在同一级， hsjday.zip 和 vipdoc 初始化后可删除。

**必填参数**：

- `--dayfiledir`：通达信 .day 文件所在目录路径
- `--dbpath`：DuckDB 数据库文件路径

### 增量更新

cron 命令会更新数据库至最新日期，包括股票数据、股本变迁数据 (gbbq)，并计算前收盘价和复权因子。

初次使用时，请在 init 后立刻执行一次 cron，以获得复权相关数据。

```bash
# 二进制安装运行
tdx2db cron --dbpath tdx.db

# 通过 docker 运行
docker run --rm --platform=linux/amd64 \
  -v "$(pwd)":/data \
  ghcr.io/jing2uo/tdx2db:latest \
  cron --dbpath /data/tdx.db

# windows docker 运行
docker run --rm --platform=linux/amd64 \
  -v "${PWD}:/data" \
  ghcr.io/jing2uo/tdx2db:latest \
  cron --dbpath /data/tdx.db


# 示例输出
📅 日线数据的最新日期为 2025-11-07
🛠 开始下载日线数据
🌲 无需下载
🛠 开始下载股本变迁数据
🔄 更新除权除息数据视图 (v_xdxr)
🔄 更新市值换手数据视图 (v_turnover)
📈 股本变迁数据更新成功
📟 计算所有股票前收盘价
🔢 复权因子导入成功
🔄 更新前复权数据视图 (v_qfq_stocks)
✅ 处理完成，耗时 14.386134606s
```

**必填参数**：

- `--dbpath`：DuckDB 数据库文件路径（使用 init 时创建的文件，db 文件可以移动，通过路径能找到即可）

### 分时数据

cron 命令支持更新 1min 或 5min 分时数据导入

```bash
# --minline 可选 1、5、1,5 ，分别表示只处理1分钟、只处理5分钟、两种都处理
tdx2db cron --dbpath tdx.db --minline 1,5

# 示例输出
...
🛠 开始下载分时数据
✅ 已下载 20251110 的数据
🛠 开始转档分笔数据
🛠 开始转换分钟数据
📊 1分钟数据导入成功
📊 5分钟数据导入成功
...
✅ 处理完成，耗时 1m45.543936302s
```

**注意**

1. 分时数据下载和导入比较耗时，数据量极大，确认需要再开启
2. 完整历史分时数据通达信没提供，请自行检索后使用 duckdb 导入，此工具无能为力
3. 要得到完整的分时线，每次更新都要明确加 --minline 参数，否则会遗漏

### 表查询

raw\_ 前缀的表名用于存储基础数据，v\_ 前缀的表名是视图

- raw_adjust_factor: 前收盘价和前复权因子
- raw_gbbq：股本变迁数据
- raw_stocks_daily： 股票日线
- raw_stocks_1min: 1 分钟 K 线(cron 导入后才有)
- raw_stocks_5min: 5 分钟 K 线(cron 导入后才有)
- v_qfq_stocks：前复权股票日线
- v_hfq_stocks：后复权股票日线
- v_xdxr：股票除权除息记录
- v_turnover：换手率和市值信息

复权数据：

```sql
# 前复权
select * from v_qfq_stocks where symbol='sz000001' order by date;

# 后复权
select * from v_hfq_stocks where symbol='sz000001' order by date;
```

前收盘价和复权因子，可以根据前收盘价拓展其他复权算法：

```sql
select * from raw_adjust_factor where symbol='sz000001';
```

复权原理参考：[点击查看](https://www.yuque.com/zhoujiping/programming/eb17548458c94bc7c14310f5b38cf25c#djL6L)

算法来自 QUANTAXIS，前复权结果和雪球、新浪两家结果一致，和同花顺及常见券商的结果不一致。

后复权结果只和 QUANTAXIS 计算结果一致，和雪球、新浪、同花顺不一致，和招商证券接近。

分时表字段和类型如下：
| symbol | open | high | low | close | amount | volume | datetime |
|:--------|:------|:------|:------|:------|:--------|:--------|:----------------|
| varchar | double | double | double | double | double | int64 | timestamp |

### 导出 Qlib CSV

Qlib 需要 "sh000001.csv" 命名的日线文件，前复权因子会变化需要单独导出。

--fromdate 是可选参数，会导出日期后（不包含当天）的股票日线，不填时全量导出，factor 始终全量导出。

```shell
docker run --rm --platform=linux/amd64 --entrypoint "" \
  -v "$(pwd)":/data \
  ghcr.io/jing2uo/tdx2db:latest \
  /export_for_qlib --db-path /data/tdx.db --output /data/aabb --fromdate 2024-01-01

# 示例输出
数据过滤启用: date > 2024-01-01
导出 DuckDB 数据中...
拆分: /data/aabb/factor.csv → /data/aabb/factor
拆分: /data/aabb/data.csv → /data/aabb/data
清理中间文件：/data/aabb/factor.csv, /data/aabb/data.csv
完成 ✅ 输出目录: /data/aabb

# Linux 可以直接下载项目根目录下的 export_for_qlib 使用，依赖 duckdb 和 awk
./export_for_qlib --db-path tdx.db --output aabb --fromdate 2024-01-01
```

运行结束后当前目录会有 aabb 文件夹，里面有 data (股票日线 csv) 和 factor(全量复权因子 csv)，使用 dump_bin.py 处理即可。

在 [ko_trading](https://github.com/jing2uo/ko_trading) 中有可执行的范例。

## 备份

1. 可以直接复制一份 db 文件，简单快捷
2. 可以用 duckdb 命令导出行情数据为 parquet 或 csv

duckdb 命令使用：

```bash
# 导出 stocks 表
duckdb tdx.db -s "copy (select * from raw_stocks_daily) to 'stocks.parquet' (format parquet, compression 'zstd')"

duckdb tdx.db -s "copy (select * from raw_stocks_daily) to 'stocks.csv' (format csv)"

# 重新建表
duckdb new.db -s "create table raw_stocks_daily as select * from read_parquet('stocks.parquet');"

duckdb new.db -s "create table raw_stocks_daily as select * from read_csv('stocks.csv');"
```

## 欢迎 issue 和 pr

有任何使用问题都可以开 issue 讨论，也期待 pr~
