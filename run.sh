#!/bin/bash
set -ex
cd `dirname $0`

# 1. 自动定位可执行文件路径（优先检查 output 目录，兼容通用打包结构与根目录直接运行）
if [ -f "./output/rocksdb-dedup" ]; then
    BIN="./output/rocksdb-dedup"
elif [ -f "./output/main" ]; then
    BIN="./output/main"
elif [ -f "./rocksdb-dedup" ]; then
    BIN="./rocksdb-dedup"
elif [ -f "./main" ]; then
    BIN="./main"
else
    echo "ERROR: rocksdb-dedup or main binary not found!" >&2
    exit 1
fi

# 确保二进制具备可执行权限
chmod +x "$BIN"

# 2. 运行时端口与配置参数（支持环境变量动态注入，兼容容器平台环境）
HTTP_PORT="${PORT:-9090}"
GRPC_PORT="${GRPC_PORT:-50051}"
DB_PATH="${DB_PATH:-./data/dedup}"
AUTH_TOKEN="${AUTH_TOKEN:-spiderhub_dedup_data}"

# 确保 RocksDB 数据存储目录存在
mkdir -p "$DB_PATH"

# 3. 配置文件判断：如果存在 dedup.toml 则使用配置文件，否则直接使用命令行参数
CONFIG_FILE=""
if [ -f "./dedup.toml" ]; then
    CONFIG_FILE="./dedup.toml"
elif [ -f "./output/dedup.toml" ]; then
    CONFIG_FILE="./output/dedup.toml"
fi

# 4. 启动服务（使用 exec 将信号直传给二进制，确保容器停止时优雅关闭与落盘）
if [ -n "$CONFIG_FILE" ]; then
    echo "Starting rocksdb-dedup with config: $CONFIG_FILE"
    exec "$BIN" serve --config "$CONFIG_FILE"
else
    echo "Starting rocksdb-dedup on HTTP :$HTTP_PORT, gRPC :$GRPC_PORT, DB: $DB_PATH"
    exec "$BIN" serve \
        --addr "0.0.0.0:${GRPC_PORT}" \
        --metrics-addr "0.0.0.0:${HTTP_PORT}" \
        --db-path "$DB_PATH" \
        --auth-token "$AUTH_TOKEN"
fi
