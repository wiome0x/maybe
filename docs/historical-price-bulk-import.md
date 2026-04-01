# 历史价格数据批量导入指南

## 概述

当 CSV 文件超过 10MB（Web UI 上传限制）时，需要通过命令行使用 rake task 直接导入数据库。

该方案使用 PostgreSQL 临时表 + `INSERT ... ON CONFLICT` 批量 upsert，150MB 文件通常在 1 分钟内完成。

## 数据流向

```
CSV 文件 (宿主机)
  │
  ▼  docker cp
容器 /tmp/SP500.csv
  │
  ▼  rake task 流式读取 (每次 5000 行)
PostgreSQL 临时表 tmp_hist_prices
  │
  ▼  单条 SQL INSERT ... ON CONFLICT
historical_prices 表
```

## CSV 格式要求

必须列：`Ticker`, `Date`, `Close`（不区分大小写）

可选列：`Open`, `High`, `Low`, `Volume`, `Adj Close`, `Currency`

日期格式固定为 `YYYY-MM-DD`。

示例：

```csv
Ticker,Date,Open,High,Low,Close,Adj Close,Volume
A,2000-01-03,47.07,47.18,40.27,43.04,43.04,4674353
A,2000-01-04,40.72,41.17,38.70,39.75,39.75,4765083
AAPL,2000-01-03,3.74,4.00,3.55,3.99,3.62,133949400
```

## 导入方式选择

| 文件大小 | 推荐方式 | 说明 |
|---------|---------|------|
| < 10MB | Web UI | 通过 Data Tracking 页面上传 |
| 10MB ~ 数 GB | rake task | 本文档描述的方式 |

## 详细操作步骤

### 第 1 步：确认容器名称

在宿主机终端执行：

```bash
docker compose -f .devcontainer/docker-compose.yml ps
```

输出示例：

```
NAME                    SERVICE   STATUS    PORTS
devcontainer-app-1      app       running   0.0.0.0:9001->3000/tcp
devcontainer-db-1       db        running   0.0.0.0:15432->5432/tcp
devcontainer-worker-1   worker    running
devcontainer-redis-1    redis     running   0.0.0.0:16379->6379/tcp
```

记住 `app` 容器的名称（如 `devcontainer-app-1`）。

### 第 2 步：将 CSV 文件复制到容器

```bash
docker cp D:\data\SP500_Historical_Data.csv devcontainer-app-1:/tmp/SP500.csv
```

> 路径说明：
> - 左侧是宿主机上的文件路径
> - 右侧是容器内的目标路径，建议放 `/tmp/`

### 第 3 步：进入容器

```bash
docker exec -it devcontainer-app-1 bash
```

### 第 4 步：确认文件

```bash
ls -lh /tmp/SP500.csv
```

应看到文件大小，例如 `156M`。

### 第 5 步：执行导入

```bash
cd /workspace

# 方式一：使用第一个 admin 用户（最简单）
bundle exec rake historical_prices:bulk_import[/tmp/SP500.csv]

# 方式二：指定用户邮箱
bundle exec rake "historical_prices:bulk_import[/tmp/SP500.csv,your@email.com]"
```

> 注意：如果参数中包含逗号，整个命令需要用引号包裹。

### 第 6 步：观察输出

正常执行输出：

```
============================================================
Historical Price Bulk Import
============================================================
  File:   /tmp/SP500.csv (156.32 MB)
  Family: cd64c7e0-3a0d-4471-9d04-4896990fda7c
  User:   admin@example.com
============================================================

[1/5] Detecting CSV structure...
  Separator: ','
  Headers:   Ticker, Date, Open, High, Low, Close, Adj Close, Volume
  Sample:    A,2000-01-03,47.07,47.18,40.27,43.04,43.04,4674353

[2/5] Scanning tickers...
  Found 503 unique tickers

[3/5] Resolving securities...
  503/503 ZTS
  Resolved 503/503 securities

[4/5] Loading CSV into temp table...
  1250000 rows...
  Loaded 1250000 rows in 18.45s

[5/5] Upserting into historical_prices...
  Upserted 1250000 records in 12.33s

============================================================
Done! 1250000 price records for 503 securities.
============================================================
```

### 第 7 步：验证数据

#### 方式一：Web UI

打开 Data Tracking 页面，在 Price Trends 区域输入 ticker（如 `AAPL`），点击 Search 查看趋势图。

#### 方式二：Rails Console

```bash
bundle exec rails console
```

```ruby
# 总记录数
HistoricalPrice.count

# 某个 ticker 的记录数
HistoricalPrice.where(ticker: "AAPL").count

# 日期范围
HistoricalPrice.where(ticker: "AAPL").order(:date).pick(:date)
# => Mon, 03 Jan 2000

HistoricalPrice.where(ticker: "AAPL").order(date: :desc).pick(:date)
# => Tue, 31 Mar 2026
```

#### 方式三：直接查询 PostgreSQL

```bash
psql -h db -U postgres -d postgres
```

```sql
SELECT ticker, COUNT(*), MIN(date), MAX(date)
FROM historical_prices
GROUP BY ticker
ORDER BY count DESC
LIMIT 10;
```

### 第 8 步：清理临时文件

```bash
rm /tmp/SP500.csv
exit
```

## rake task 内部原理

### 5 步流程

1. **检测 CSV 结构** — 读取前 3 行，自动识别分隔符和列头（大小写不敏感）
2. **扫描 ticker** — 流式遍历整个 CSV，收集所有唯一 ticker 到 `Set`，内存恒定
3. **解析 securities** — 对每个唯一 ticker 调用 `Security::Resolver`，优先匹配数据库已有记录，找不到则创建 offline security。结果缓存在 `security_map` 中
4. **流式写入临时表** — 每 5000 行做一次 `INSERT INTO tmp_hist_prices VALUES (...)`，不会把整个文件加载到内存
5. **单条 SQL upsert** — 从临时表 JOIN security_map 一次性 `INSERT INTO historical_prices ... ON CONFLICT DO UPDATE`，数据库内部操作，极快

### 为什么不用 Web UI

| 问题 | 原因 |
|------|------|
| nginx 默认限制 1MB | `client_max_body_size` 需要额外配置 |
| CSV 内容存 DB string 字段 | `imports.raw_file_str` 是 varchar，大文件会撑爆内存 |
| 全量 CSV.parse | 解析 150MB 字符串会消耗大量内存和 CPU |
| 逐行 upsert | 原始实现每行一次 DB 操作，10 万行就是 10 万次 |

### 为什么用临时表而不是直接 INSERT

- 临时表不写 WAL 日志，写入速度快
- 可以在数据库内部做 JOIN + 类型转换，避免 Ruby 层逐行处理
- 单条 upsert SQL 比逐行 upsert 快 10~50 倍
- 临时表在连接断开后自动清理

## 常见问题

### Q: 导入报错 "Missing required columns"

检查 CSV 第一行的列头是否包含 `Ticker`、`Date`、`Close`。列名不区分大小写，但必须存在。

### Q: 部分 ticker 显示 "WARNING: Failed to resolve"

说明 `Security::Resolver` 无法在数据库或外部 provider 中找到该 ticker。这些 ticker 的数据会被跳过。通常是因为 ticker 已退市或拼写有误。

### Q: 重复导入会怎样

安全的。`ON CONFLICT (family_id, security_id, date) DO UPDATE` 会覆盖已有记录的 open/high/low/close/volume 值。不会产生重复数据。

### Q: 导入后趋势图看不到数据

确认搜索的 ticker 大小写正确（数据库中存储为大写）。确认日期范围覆盖了导入数据的时间段。

### Q: 如何删除已导入的数据

```ruby
# Rails console 中
# 删除某个 family 的所有历史价格
HistoricalPrice.where(family_id: "your-family-id").delete_all

# 删除某个 ticker 的数据
HistoricalPrice.where(ticker: "AAPL").delete_all
```
