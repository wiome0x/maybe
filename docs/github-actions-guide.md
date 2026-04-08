# GitHub Actions CI/CD 指南

## Workflow 文件总览

```text
.github/workflows/
├── ci.yml        # 持续集成（可复用，被其他 workflow 调用）
├── pr.yml        # Pull Request 自动检查
└── publish.yml   # 构建并发布 Docker 镜像（GHCR + 可选 Docker Hub）
```

调用关系：

```text
pr.yml ──────────> ci.yml（PR 提交时触发）
publish.yml ─────> ci.yml ─────> build + push image
```

---

## ci.yml（持续集成）

触发方式：仅通过 `workflow_call` 被其他 workflow 调用，不独立运行。

主要检查：
- Ruby 安全扫描（Brakeman）
- JS 依赖安全扫描（importmap audit）
- Ruby Lint（RuboCop）
- JS Lint（Biome）
- 测试（Minitest + System Test）

---

## pr.yml（Pull Request 检查）

触发方式：PR 创建/更新时自动触发。  
功能：调用 `ci.yml` 执行完整检查。

---

## publish.yml（镜像发布）

当前触发方式：

1. 手动触发 `workflow_dispatch`
2. 推送 tag（`v*`）

说明：
- 当前配置不在 `main` push 时自动发布镜像
- 发布前会先跑 `ci.yml`，CI 通过才会构建
- 默认推送 GHCR；配置完成后可同时推送 Docker Hub

---

## 当前镜像标签策略

当触发 tag（如 `v1.2.3`）时：
- `1.2.3`
- `stable`
- `latest`
- `sha-<commit-long>`

当手动触发时（非 tag ref）：
- `sha-<commit-long>`

---

## GHCR（默认已启用）

推送地址：

```text
ghcr.io/<owner>/<repo>:<tag>
```

你无需额外配置 GHCR 密钥，`publish.yml` 使用 `GITHUB_TOKEN` 登录。

---

## 启用 Docker Hub 同步发布

`publish.yml` 已支持 Docker Hub 条件发布。只要配置以下参数，就会在同一条 workflow 中同时推送到 Docker Hub。

### 1. 配置 GitHub Secrets

仓库路径：`Settings -> Secrets and variables -> Actions -> Secrets`

新增：
- `DOCKERHUB_USERNAME`：Docker Hub 用户名
- `DOCKERHUB_TOKEN`：Docker Hub Access Token（建议不要使用账号密码）

### 2. 配置 GitHub Variables

仓库路径：`Settings -> Secrets and variables -> Actions -> Variables`

新增：
- `DOCKERHUB_IMAGE`

示例值：

```text
yourname/maybe
```

### 3. 触发发布

方式 A（推荐正式发布）：

```bash
git tag v1.0.0
git push origin v1.0.0
```

方式 B（手动）：
- Actions -> Publish Docker image -> Run workflow
- 输入 `ref`（如 `main` 或具体 commit SHA）

---

## 拉取示例

GHCR：

```bash
docker pull ghcr.io/<owner>/<repo>:stable
```

Docker Hub：

```bash
docker pull yourname/maybe:stable
```

---

## 常见问题

Q: 为什么配置了 Docker Hub 但没有推送？  
A: 检查这三项是否都已配置：`DOCKERHUB_IMAGE`、`DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`。任意缺失都会跳过 Docker Hub 步骤。

Q: Fork 后 Actions 不运行？  
A: 进入 Actions 页面启用 workflow，并确认仓库 Actions 权限允许运行。

Q: 报权限不足无法推送 GHCR？  
A: 检查仓库设置中 Actions 权限，确保 workflow 拥有 `packages: write`（当前 `publish.yml` 已配置）。

Q: 构建很慢怎么办？  
A: 首次双架构构建较慢，后续依赖 `cache-from/cache-to type=gha` 会明显加速。

Q: 只想构建 amd64？  
A: 将 `publish.yml` 中 `platforms: 'linux/amd64,linux/arm64'` 改为 `platforms: 'linux/amd64'`。
