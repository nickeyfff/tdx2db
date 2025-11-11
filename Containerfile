FROM --platform=linux/amd64 docker.io/library/debian:sid-slim

# 安装系统依赖和Python环境
RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    gzip \
    python3.12 \
    python3.12-pip \
    python3.12-venv \
    build-essential \
    wget \
    && update-ca-certificates \
    && apt-get clean

# 安装uv包管理器
RUN wget -qO- https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# 安装ta-lib库
RUN wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz && \
    tar -xzf ta-lib-0.4.0-src.tar.gz && \
    cd ta-lib/ && \
    ./configure --prefix=/usr/local && \
    make && \
    make install && \
    cd .. && \
    rm -rf ta-lib ta-lib-0.4.0-src.tar.gz

# 复制tdx2db相关文件
COPY linux/amd64/tdx2db /
COPY export_for_qlib /

# 安装DuckDB CLI
RUN wget -q https://install.duckdb.org/v1.4.1/duckdb_cli-linux-amd64.gz && \
    gzip -d duckdb_cli-linux-amd64.gz && \
    mv duckdb_cli-linux-amd64 /bin/duckdb && \
    ln -sf /bin/duckdb /duckdb

# 复制ko_trading代码并安装Python依赖
COPY ko_trading /opt/ko_trading
WORKDIR /opt/ko_trading
RUN uv pip install -r req.txt

# 创建统一入口脚本
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /tdx2db /export_for_qlib /bin/duckdb

# 设置工作目录和入口点
WORKDIR /
ENV PATH="/opt/ko_trading:$PATH"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
