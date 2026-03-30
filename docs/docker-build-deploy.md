# Maybe Docker 镜像构建与发布指南

## 前置要求

- Docker Engine 20.10+（支持 BuildKit）
- Docker Compose v2+（用于本地运行）
- Docker Hub / GitHub Container Registry / 私有仓库账号（用于发布）
- Git

---

## 1. 构建 Docker 镜像

### 1.1 基本构建

```bash
docker build -t maybe:latest .
```

### 1.2 带版本标签构建

```bash
# 使用 git commit SHA 作为构建标识
docker build \
  --build-arg BUILD_COMMIT_SHA=$(git rev-parse HEAD) \
  -t maybe:$(git describe --tags --always) \
  -t maybe:latest \
  .
```

### 1.3 多平台构建（适用于 ARM/AMD64 混合部署）

```bash
docker buildx create --name maybe-builder --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BUILD_COMMIT_SHA=$(git rev-parse HEAD) \
  -t your-registry/maybe:latest \
  --push \
  .
```

### 构建过程说明

Dockerfile 采用多阶段构建（multi-stage build）：

1. **base 阶段**：安装运行时依赖（libvips、PostgreSQL 客户端、libyaml）
2. **build 阶段**：安装编译依赖 → `bundle install` → bootsnap 预编译 → 资产预编译
3. **最终阶段**：仅复制构建产物，以非 root 用户（uid 1000）运行

---

## 2. 本地运行测试

### 2.1 创建 docker-compose.yml

```yaml
services:
  app:
    image: maybe:latest
    ports:
      - "3000:3000"
    environment:
      SELF_HOSTED: "true"
      SECRET_KEY_BASE: "your-secret-key-base-at-least-64-chars-long-generate-with-openssl-rand-hex-64"
      DB_HOST: db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      REDIS_URL: redis://redis:6379/1
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

  worker:
    image: maybe:latest
    command: bundle exec sidekiq
    environment:
      SELF_HOSTED: "true"
      SECRET_KEY_BASE: "your-secret-key-base-at-least-64-chars-long-generate-with-openssl-rand-hex-64"
      DB_HOST: db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      REDIS_URL: redis://redis:6379/1
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

  db:
    image: postgres:16
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    volumes:
      - redis-data:/data

volumes:
  postgres-data:
  redis-data:
```

### 2.2 启动服务

```bash
# 生成 SECRET_KEY_BASE
export SECRET_KEY_BASE=$(openssl rand -hex 64)

# 启动
docker compose up -d

# 查看日志
docker compose logs -f app
```

### 2.3 验证

- 浏览器访问 `http://localhost:3000`
- 首次启动会自动执行 `rails db:prepare`（创建数据库 + 运行迁移）

---

## 3. 发布镜像

### 3.1 发布到 Docker Hub

```bash
# 登录
docker login

# 打标签
docker tag maybe:latest your-dockerhub-username/maybe:latest
docker tag maybe:latest your-dockerhub-username/maybe:v1.0.0

# 推送
docker push your-dockerhub-username/maybe:latest
docker push your-dockerhub-username/maybe:v1.0.0
```

### 3.2 发布到 GitHub Container Registry (ghcr.io)

```bash
# 登录（使用 GitHub Personal Access Token）
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 打标签
docker tag maybe:latest ghcr.io/your-org/maybe:latest
docker tag maybe:latest ghcr.io/your-org/maybe:v1.0.0

# 推送
docker push ghcr.io/your-org/maybe:latest
docker push ghcr.io/your-org/maybe:v1.0.0
```

### 3.3 发布到私有仓库

```bash
# 登录
docker login your-registry.example.com

# 打标签并推送
docker tag maybe:latest your-registry.example.com/maybe:latest
docker push your-registry.example.com/maybe:latest
```

---

## 4. 生产部署配置

### 4.1 必需环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `SELF_HOSTED` | 启用自托管模式 | `true` |
| `SECRET_KEY_BASE` | Rails 加密密钥（`openssl rand -hex 64` 生成） | `a1b2c3...` |
| `DB_HOST` | PostgreSQL 主机 | `db` |
| `POSTGRES_USER` | 数据库用户 | `postgres` |
| `POSTGRES_PASSWORD` | 数据库密码 | `your-secure-password` |
| `REDIS_URL` | Redis 连接地址 | `redis://redis:6379/1` |

### 4.2 可选环境变量

| 变量 | 说明 |
|------|------|
| `SYNTH_API_KEY` | Synth API 密钥（汇率/股价） |
| `OPENAI_ACCESS_TOKEN` | OpenAI API 密钥（AI 功能） |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` | 邮件发送配置 |
| `APP_DOMAIN` | 应用域名（用于邮件链接） |
| `ACTIVE_STORAGE_SERVICE` | 文件存储（`amazon` 或 `cloudflare`） |
| `PLAID_CLIENT_ID` / `PLAID_SECRET` | Plaid 银行数据同步 |

### 4.3 数据持久化

确保以下目录/卷已挂载：

- PostgreSQL 数据：`/var/lib/postgresql/data`
- Redis 数据：`/data`
- Rails 存储（如使用本地磁盘）：`/rails/storage`

---

## 5. CI/CD 自动化示例（GitHub Actions）

```yaml
name: Build and Push Docker Image

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract version tag
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          build-args: |
            BUILD_COMMIT_SHA=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## 6. 常用运维命令

```bash
# 查看容器状态
docker compose ps

# 进入 Rails 控制台
docker compose exec app bin/rails console

# 手动运行数据库迁移
docker compose exec app bin/rails db:migrate

# 查看 Sidekiq 日志
docker compose logs -f worker

# 重启应用（更新镜像后）
docker compose pull
docker compose up -d

# 备份数据库
docker compose exec db pg_dump -U postgres maybe_production > backup.sql
```
