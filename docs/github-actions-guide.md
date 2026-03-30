# GitHub Actions CI/CD 指南

## Workflow 文件总览

```
.github/workflows/
├── ci.yml        # 持续集成（可复用，被其他 workflow 调用）
├── pr.yml        # Pull Request 自动检查
└── publish.yml   # 构建并发布 Docker 镜像
```

调用关系：

```
pr.yml ──────────→ ci.yml（PR 提交时触发）
publish.yml ─────→ ci.yml → build Docker（推送 main/tag 时触发）
```

---

## ci.yml — 持续集成

**触发方式**：仅通过 `workflow_call` 被其他 workflow 调用，不会独立运行。

包含 5 个并行 Job：

| Job | 工具 | 作用 |
|-----|------|------|
| `scan_ruby` | Brakeman | 扫描 Ruby 代码安全漏洞 |
| `scan_js` | importmap audit | 扫描 JS 依赖安全漏洞 |
| `lint` | RuboCop | 检查 Ruby 代码风格 |
| `lint_js` | Biome | 检查 JS 代码风格和格式 |
| `test` | Minitest | 启动 PostgreSQL + Redis，运行单元/集成/系统测试 |

测试 Job 会：
1. 安装 Chrome（系统测试需要）、libvips（图片处理）、PostgreSQL 客户端
2. 创建数据库并加载 schema
3. 运行 seed 数据
4. 执行 `bin/rails test`（单元+集成）
5. 执行 `bin/rails test:system`（浏览器测试）
6. 失败时上传截图到 Artifacts

---

## pr.yml — Pull Request 检查

**触发方式**：任何 Pull Request 创建或更新时自动触发。

功能：调用 `ci.yml` 运行全部 5 项检查。PR 页面会显示检查状态，可配合 Branch Protection Rules 强制要求通过后才能合并。

---

## publish.yml — 构建并发布 Docker 镜像

**触发方式**（三种）：

| 触发条件 | 生成的标签 |
|----------|-----------|
| 推送到 `main` 分支 | `latest`, `sha-<commit>` |
| 推送 `v*` 标签（如 `v1.0.0`） | `stable`, `1.0.0`, `sha-<commit>` |
| 手动触发（workflow_dispatch） | 根据指定的 ref 决定 |

**构建流程**：
1. 先运行 `ci.yml` 全部检查
2. CI 通过后，使用 Docker Buildx 构建 `linux/amd64` + `linux/arm64` 双平台镜像
3. 推送到 GitHub Container Registry (`ghcr.io`)
4. 使用 GitHub Actions Cache 加速后续构建

**镜像地址**：`ghcr.io/<owner>/<repo>:<tag>`

---

## Fork 项目发布到自己的镜像仓库

### 方案一：发布到自己的 GitHub Container Registry（推荐，零配置）

Fork 后 `${{ github.repository }}` 自动变为 `your-username/maybe`，无需修改任何文件。

**启用步骤**：

1. 进入 fork 仓库 → Settings → Actions → General
2. Workflow permissions 选择 **Read and write permissions**
3. 勾选 **Allow GitHub Actions to create and approve pull requests**（可选）
4. 触发构建：

```bash
# 方式一：打 tag 发布正式版
git tag v1.0.0
git push origin v1.0.0
# 镜像：ghcr.io/your-username/maybe:stable, :1.0.0

# 方式二：推送 main 发布最新版
git push origin main
# 镜像：ghcr.io/your-username/maybe:latest

# 方式三：GitHub 页面手动触发
# Actions → Publish Docker image → Run workflow → 输入 ref
```

**拉取镜像**：
```bash
docker pull ghcr.io/your-username/maybe:latest
```

> 注意：ghcr.io 镜像默认为私有。如需公开访问：
> 仓库页面 → Packages → 点击镜像 → Package settings → Change visibility → Public

---

### 方案二：发布到 Docker Hub

需要修改 `publish.yml` 并配置 Secrets。

**第一步：在 Docker Hub 创建仓库**

登录 https://hub.docker.com → Create Repository → 命名为 `maybe`

**第二步：在 GitHub 仓库配置 Secrets**

Settings → Secrets and variables → Actions → New repository secret：

| Secret 名称 | 值 |
|-------------|-----|
| `DOCKERHUB_USERNAME` | 你的 Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（在 Docker Hub → Account Settings → Security → New Access Token 生成） |

**第三步：修改 `publish.yml`**

将 `env` 和登录步骤改为：

```yaml
env:
  REGISTRY: docker.io
  IMAGE_NAME: your-dockerhub-username/maybe
```

登录步骤改为：

```yaml
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
```

完整修改后的 build job steps 参考：

```yaml
    steps:
      - name: Check out the repo
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.ref || github.ref }}

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          flavor: latest=auto
          tags: |
            type=sha,format=long
            type=semver,pattern={{version}}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
            type=raw,value=stable,enable=${{ startsWith(github.ref, 'refs/tags/v') }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          platforms: 'linux/amd64,linux/arm64'
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: false
          build-args: BUILD_COMMIT_SHA=${{ github.sha }}
```

**拉取镜像**：
```bash
docker pull your-dockerhub-username/maybe:latest
```

---

### 方案三：同时发布到 ghcr.io 和 Docker Hub

在 `metadata-action` 的 `images` 中指定多个地址，并添加两个登录步骤：

```yaml
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ghcr.io/${{ github.repository }}
            ${{ secrets.DOCKERHUB_USERNAME }}/maybe
          flavor: latest=auto
          tags: |
            type=sha,format=long
            type=semver,pattern={{version}}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
            type=raw,value=stable,enable=${{ startsWith(github.ref, 'refs/tags/v') }}
```

---

## 常见问题

**Q: Fork 后 Actions 没有运行？**
A: GitHub 默认禁用 fork 仓库的 Actions。进入 Actions 页面，点击 "I understand my workflows, go ahead and enable them"。

**Q: 构建失败提示权限不足？**
A: 检查 Settings → Actions → General → Workflow permissions 是否设为 "Read and write permissions"。

**Q: 如何跳过 CI 直接构建镜像？**
A: 当前 `publish.yml` 中 `build` job 依赖 `ci` job（`needs: [ci]`）。如需跳过，可移除 `needs` 行和 `ci` job 引用，但不推荐。

**Q: 构建超时？**
A: 当前超时设为 60 分钟。双平台构建首次可能较慢（约 20-30 分钟），后续有缓存会快很多（约 5-10 分钟）。

**Q: 如何只构建单平台加速？**
A: 将 `platforms: 'linux/amd64,linux/arm64'` 改为 `platforms: 'linux/amd64'`。
