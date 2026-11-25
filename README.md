# RocksDB Dedup (高性能持久化去重引擎)

[![Release](https://img.shields.io/github/v/release/wangjingyu001/rocksdb_demp?color=blue)](https://github.com/wangjingyu001/rocksdb_demp/releases)
[![Rust](https://img.shields.io/badge/rust-1.70%2B-orange.svg)](https://www.rust-lang.org/)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20macOS-lightgrey.svg)](https://github.com/wangjingyu001/rocksdb_demp/releases)

`rocksdb-dedup` 是一个专为**海量网络爬虫、搜索引擎与流式数据管道**设计的高性能、持久化、低成本去重服务。

基于 Rust 原生开发，结合 **RocksDB 嵌入式 LSM-Tree 存储引擎** 与 **动态分层内存布隆过滤器 (Layered Bloom Filter)**，实现单机数十亿级数据容量下的微秒级去重，内存占用仅为传统纯内存 Redis 方案的 **1/10 ~ 1/20**。

---

## 🌟 核心特性

- **🚀 极致双层加速架构**：
  - **热路径（布隆过滤器）**：内存直接拦截 99% 以上非重复请求，判定不存在耗时仅 **微秒级**，无磁盘 I/O。
  - **冷路径（RocksDB 双 Column Family）**：精准比对原始 Key，彻底消除布隆过滤器的假阳性（误判）与 Hash 冲突。
- **🌐 原生双协议支持**：
  - **HTTP RESTful API**：原生集成 Axum 高并发 HTTP 引擎（`/api/v1/check`、`batch_check`、`exists` 等），微服务与通用爬虫直接通过 HTTP 即可调用。
  - **gRPC (HTTP/2 + Protobuf)**：极高吞吐量 RPC 接口，支持批量批处理与流式调用。
- **⏱️ 完善的 TTL 生命周期与自动垃圾回收**：
  - 支持设置精确到毫秒的绝对过期时间戳（`expire_at_ms`），支持**永久去重**与**滑动/周期性去重**。
  - 独立的后台自适应清理线程（Adaptive Cleaner），自动根据积压量按阶梯提速清理过期数据，并自动触发 RocksDB `compact_range` 物理回收磁盘碎片。
- **🔒 统一安全鉴权 (Auth Token)**：
  - 支持配置访问密钥，通过 `Authorization: Bearer <token>` 或 `X-API-Key: <token>` 进行全局统一拦截认证。
- **📦 超强兼容与零依赖运行**：
  - 预编译 Linux 二进制采用 Ubuntu 18.04 编译基线，静态内嵌 C++ 运行时（`libstdc++`），最低兼容 **GLIBC 2.27+**，在 Debian 10/11/12、Ubuntu、CentOS 8 以及各类无依赖容器环境（如 ByteFaaS/Docker）中开箱即用。
- **📊 工业级可观测性**：
  - 内置 Prometheus 指标端点（`/metrics`）与健康探针（`/health`），附带开箱即用的 Grafana 监控大盘模板。

---

## 🏗️ 架构设计

```
                      客户端请求 (HTTP RESTful / gRPC)
                                   │
                                   ▼
                    ┌───────────────────────────────┐
                    │  Token 统一安全鉴权拦截器     │
                    └──────────────┬────────────────┘
                                   │
                                   ▼
                    ┌───────────────────────────────┐
                    │ 动态分层内存布隆过滤器 (Bloom)│
                    └──────────────┬────────────────┘
                                   │
                     ┌─────────────┴─────────────┐
                     │ 判定绝对不存在             │ 判定可能存在
                     ▼                           ▼
        ┌─────────────────────────┐  ┌─────────────────────────┐
        │ 写入 RocksDB cf_dedup   │  │ 查询 RocksDB cf_dedup   │
        │ 插入布隆过滤器          │  │ 比对原始 Key 校验冲突   │
        │ 返回: status=inserted   │  └───────────┬─────────────┘
        └─────────────────────────┘              │
                                   ┌─────────────┴─────────────┐
                                   │ 未过期                    │ 已过期
                                   ▼                           ▼
                      ┌─────────────────────────┐  ┌─────────────────────────┐
                      │ 返回: status=duplicate  │  │ 覆盖新值，删除旧索引   │
                      │ is_duplicate=true       │  │ 返回: expired_and_replaced
                      └─────────────────────────┘  └─────────────────────────┘
```

---

## 🚀 快速上手

### 1. 下载预编译二进制（推荐）

从 [GitHub Releases](https://github.com/wangjingyu001/rocksdb_demp/releases) 直接下载对应平台的预编译安装包：

```bash
# 下载 Linux x86_64 最新兼容版 (v0.2.6)
curl -L -o rocksdb-dedup-linux-x86_64.tar.gz \
  https://github.com/wangjingyu001/rocksdb_demp/releases/download/v0.2.6/rocksdb-dedup-linux-x86_64.tar.gz

# 解压并授权
tar -zxvf rocksdb-dedup-linux-x86_64.tar.gz
chmod +x ./rocksdb-dedup

# 验证版本
./rocksdb-dedup --version
```

### 2. 命令行前台启动服务

```bash
./rocksdb-dedup serve \
  --addr 0.0.0.0:50051 \
  --metrics-addr 0.0.0.0:9090 \
  --db-path ./data/dedup \
  --auth-token spiderhub_dedup_data
```

启动后控制台将输出服务就绪日志：
- **gRPC 服务** 监听在 `0.0.0.0:50051`
- **HTTP RESTful API / 监控端点** 监听在 `0.0.0.0:9090`

### 3. 使用配置文件启动 (推荐生产使用)

参考项目根目录的 `dedup.example.toml` 复制一份 `dedup.toml`：

```bash
cp dedup.example.toml dedup.toml
./rocksdb-dedup serve --config dedup.toml
```

### 4. 容器 / ByteFaaS 一键启动

项目中已内置全自动检测与信号优雅管理的 `run.sh`：

```bash
chmod +x run.sh
./run.sh
```

---

## 📡 HTTP 业务接口与调试指南

默认 HTTP 端口为 `9090`。若启动时配置了 `--auth-token`，请求头需携带：  
`-H "Authorization: Bearer <auth-token>"` 或 `-H "X-API-Key: <auth-token>"`。

### 1. 健康检查 (探针使用，无需鉴权)

```bash
curl -X GET http://127.0.0.1:9090/health
```
```json
{
  "cleaner_paused": false,
  "service": "rocksdb-dedup",
  "status": "UP",
  "timestamp_ms": 1794371234567
}
```

---

### 2. 单条查重并写入 (`/api/v1/check`)

> 最常用的接口，一次请求完成判断与原子写入。

#### ① 首次请求（新 URL，未抓取过）
```bash
curl -X POST http://127.0.0.1:9090/api/v1/check \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer spiderhub_dedup_data" \
  -d '{
    "namespace": "spider_news",
    "key": "https://news.sina.com.cn/article/1001",
    "expire_at_ms": 4102444800000,
    "metadata": "{\"crawler\": \"worker_1\"}"
  }'
```
**响应：**
```json
{
  "status": "inserted",
  "is_duplicate": false,
  "value": null
}
```

#### ② 第二次请求相同的 Key（判定重复）
```bash
curl -X POST http://127.0.0.1:9090/api/v1/check \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer spiderhub_dedup_data" \
  -d '{
    "namespace": "spider_news",
    "key": "https://news.sina.com.cn/article/1001"
  }'
```
**响应：**
```json
{
  "status": "duplicate",
  "is_duplicate": true,
  "value": {
    "created_at_ms": 1794371234567,
    "expire_at_ms": 4102444800000,
    "metadata": "{\"crawler\": \"worker_1\"}"
  }
}
```

---

### 3. 批量查重并写入 (`/api/v1/batch_check`)

支持一次传入多个 Key，引擎内部并发查询与批量写入：

```bash
curl -X POST http://127.0.0.1:9090/api/v1/batch_check \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer spiderhub_dedup_data" \
  -d '{
    "namespace": "spider_news",
    "items": [
      {"key": "https://news.sina.com.cn/article/1001"},
      {"key": "https://news.sina.com.cn/article/1002"},
      {"key": "https://news.sina.com.cn/article/1003"}
    ]
  }'
```
**响应：**
```json
{
  "total": 3,
  "results": [
    {"key": "https://news.sina.com.cn/article/1001", "status": "duplicate", "is_duplicate": true, "value": {...}},
    {"key": "https://news.sina.com.cn/article/1002", "status": "inserted", "is_duplicate": false, "value": null},
    {"key": "https://news.sina.com.cn/article/1003", "status": "inserted", "is_duplicate": false, "value": null}
  ]
}
```

---

### 4. 只查不写 (`/api/v1/exists`)

```bash
curl -X POST http://127.0.0.1:9090/api/v1/exists \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer spiderhub_dedup_data" \
  -d '{
    "namespace": "spider_news",
    "key": "https://news.sina.com.cn/article/1001"
  }'
```
**响应：** `{"exists": true}`

---

### 5. 删除 Key (`/api/v1/delete`)

用于重置特定 URL 的抓取状态，使其后续可重新抓取：

```bash
curl -X POST http://127.0.0.1:9090/api/v1/delete \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer spiderhub_dedup_data" \
  -d '{
    "namespace": "spider_news",
    "key": "https://news.sina.com.cn/article/1001"
  }'
```
**响应：** `{"deleted": true}`

---

## 🐍 Python 客户端调用

### 1. 使用 HTTP 直接调用（极简无额外依赖）

```python
import requests

url = "http://127.0.0.1:9090/api/v1/check"
headers = {"Authorization": "Bearer spiderhub_dedup_data"}

resp = requests.post(url, headers=headers, json={
    "namespace": "spider_news",
    "key": "https://example.com/article/1",
    "expire_at_ms": 4102444800000 # 永久有效
}).json()

if resp.get("is_duplicate"):
    print("URL 已抓取过，跳过")
else:
    print("新 URL，开始抓取")
```

### 2. 使用官方 gRPC 客户端 SDK

SDK 位于 `clients/python/` 目录下（支持单机客户端与分布式分片客户端）：

```python
from dedup_client import DedupClient

with DedupClient("127.0.0.1:50051", auth_token="spiderhub_dedup_data") as client:
    status = client.check_and_set(
        namespace="spider_news",
        key=b"https://example.com/article/1",
        expire_at_ms=4102444800000,
        metadata=b'{"source": "crawler_v1"}'
    )
    print("去重结果:", status) # inserted / duplicate / expired_and_replaced
```

---

## ⚙️ 核心参数说明：`expire_at_ms` 设置规范

`expire_at_ms` 是一个 **绝对毫秒级 Unix 时间戳**（即 URL 在未来的具体失效时刻），**不是** Redis 中的相对 TTL 秒数。

| 取值设置 | 含义与效果 | 典型应用场景 |
| :--- | :--- | :--- |
| **`4102444800000`** (2100年) | **永久去重，永不过期**（除非主动调接口删除） | 新闻文章、论文专利、公告归档等静态页面 |
| **`当前时间戳 + N*86400*1000`** | **滑动/周期性去重**，到达指定时间后自动失效，允许重爬 | 电商商品比价、热点榜单追踪、用户动态爬虫 |
| **`0`** | 等价于 1970 年，**立即视为过期** | 临时调试 / 刷新重写验证 |

*动态计算 N 天后过期的 Python 代码示例：*
```python
import time
# 7 天后过期
expire_at_7d = int(time.time() * 1000) + 7 * 86400 * 1000
```

---

## ⚠️ 生产环境关键部署注意事项 (踩坑必读)

### 1. 严格禁止多个实例挂载同一个数据目录 (`--db-path`)
* **原理**：RocksDB 是**单进程独占**的嵌入式存储库，会在目录下加持物理文件锁（`LOCK` 文件）。
* **后果**：如果启动了两个容器或进程指向同一个数据目录，后启动的实例会因无法获取锁而**直接报错退出**。每个实例必须独占其专属的本地磁盘路径。

### 2. 避免在多实例前直接使用无状态轮询（Round-Robin）负载均衡
* **原理**：去重服务是有状态的（Stateful）。如果配置了多实例且各自拥有独立数据库，前置负载均衡若进行无序随机轮询分发，同一个 URL 第一次落在实例 A，第二次落在实例 B，**实例 B 内部无此数据，去重将彻底失效**。

### 3. 最佳实践方案推荐

#### 方案 A：优先单实例部署（满足 99% 的应用场景）
* **性能充裕**：由于热路径由内存布隆过滤器支撑，单台普通 4C8G 容器单实例即可支撑 **30,000 ~ 50,000 QPS**，足以承载每天数亿级抓取量的爬虫系统。
* **部署建议**：在云平台 / ByteFaaS / K8s Deployment 中配置：
  - `min_replicas = 1`
  - `max_replicas = 1`（固定单实例）
  - 挂载持久化存储卷（Persistent Volume）到 `--db-path`，确保容器重建后数据不丢失。

#### 方案 B：超大规模场景使用客户端分片（Sharded Consistent Hashing）
* 若数据量达到几十亿且必须使用多台物理机承载，可部署多个独立节点，客户端使用 SDK 提供的 `ShardedDedupClient`：
  ```python
  from dedup_client import ShardedDedupClient

  nodes = ["10.0.0.1:50051", "10.0.0.2:50051", "10.0.0.3:50051"]
  client = ShardedDedupClient(nodes, auth_token="spiderhub_dedup_data")
  # SDK 内部基于一致性哈希环计算，相同的 URL 保证永远路由到同一台物理节点
  ```

---

## 📊 监控与运维

### 1. Prometheus 监控指标

直接访问 `http://<IP>:9090/metrics`，可收集以下关键指标：

- `rocksdb_dedup_bloom_capacity`: 布隆过滤器设计容量
- `rocksdb_dedup_bloom_inserted`: 布隆过滤器已插入条数
- `rocksdb_dedup_bloom_checks_total`: 总查重请求数
- `rocksdb_dedup_bloom_hits_total`: 布隆过滤器命中数
- `rocksdb_dedup_keys_estimate`: RocksDB 总 Key 估算量
- `rocksdb_dedup_cleaner_scanned_keys_total`: 已扫描清理的过期 Key 总量

### 2. Grafana 监控大盘

项目在 `grafana/rocksdb_dedup_dashboard.json` 提供了官方大盘模板，导入 Grafana 即可直观监控：
- **实时查重 QPS & 延迟分位值（P99/P95）**
- **布隆过滤器命中率曲线**
- **后台过期清理速率与积压水位**
- **RocksDB 磁盘读写与 Compact 回收状态**

---

## 🛠️ 从源码编译构建

环境要求：Rust 1.70+、Clang、CMake、Git。

```bash
# 1. 克隆主仓库
git clone https://github.com/wangjingyu001/rocksdb_demp.git
cd rocksdb_demp

# 2. 编译发布包（启用最大 C++ 静态内嵌优化）
RUSTFLAGS='-C link-arg=-static-libstdc++ -C link-arg=-static-libgcc' cargo build --release

# 3. 运行全部单元测试（40 个测试）
cargo test

# 4. 产物路径
./target/release/rocksdb-dedup --help
```

---

## 📄 License

本项目基于 [MIT](LICENSE) / [Apache-2.0](LICENSE) 双协议开源。
