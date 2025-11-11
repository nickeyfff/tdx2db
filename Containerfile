FROM --platform=linux/amd64 python:3.12-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 安装uv包管理器
RUN pip install uv

# 安装ta-lib库
RUN wget -qO- https://sourceforge.net/projects/ta-lib/files/ta-lib/0.4.0/ta-lib-0.4.0-src.tar.gz/download | tar -xz && \
    cd ta-lib/ && \
    ./configure --prefix=/usr/local && \
    make && \
    make install && \
    cd .. && \
    rm -rf ta-lib

# 更新动态链接库缓存
RUN ldconfig

# 复制tdx2db相关文件
COPY linux/amd64/tdx2db /tdx2db
COPY export_for_qlib /export_for_qlib

# 安装DuckDB CLI
RUN wget -q https://install.duckdb.org/v1.4.1/duckdb_cli-linux-amd64.gz && \
    gzip -d duckdb_cli-linux-amd64.gz && \
    mv duckdb_cli-linux-amd64 /bin/duckdb && \
    chmod +x /bin/duckdb

# 复制ko_trading代码
COPY ko_trading /opt/ko_trading

# 安装Python依赖
WORKDIR /opt/ko_trading
RUN uv pip install --system -r req.txt

# 复制入口脚本
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# 设置权限
RUN chmod +x /usr/local/bin/entrypoint.sh /tdx2db /export_for_qlib /bin/duckdb

# 设置工作目录和环境
WORKDIR /
ENV PATH="/opt/ko_trading:$PATH"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
