# Maybe 远程开发环境部署指南

## 服务器要求

| 项目 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 2 核 | 4 核 |
| 内存 | 4 GB | 8 GB |
| 硬盘 | 40 GB SSD | 60 GB SSD |
| 系统 | CentOS 7+ / Ubuntu 20.04+ | CentOS 9+ / Ubuntu 22.04+ |

## 〇、本地 SSH 配置（Windows）

### 1. 上传 SSH 公钥到服务器

```powershell
# 首次需要用密码登录完成上传
type $env:USERPROFILE\.ssh\bond.rsa.pub | ssh root@your-server-ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### 2. 配置 SSH 快捷连接

编辑本地 `~/.ssh/config`：

```
Host maybe-dev
    HostName your-server-ip
    User root
    Port 22
    IdentityFile ~/.ssh/bond.rsa
```

之后可直接使用：

```powershell
ssh maybe-dev
```

### 3. 在 Kiro / VS Code 中连接

安装 `Remote - SSH` 扩展后，按 `F1` → `Remote-SSH: Connect to Host` → 选择 `maybe-dev`。

## 一、服务器环境准备

### 1. 安装 Docker 和 Docker Compose

**CentOS 9：**

```bash
dnf install -y dnf-plugins-core git
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl start docker
systemctl enable docker
```

**CentOS 7/8：**

```bash
yum install -y yum-utils git
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl start docker
systemctl enable docker
```

**Ubuntu：**

```bash
curl -fsSL https://get.docker.com | sh
apt install -y git
systemctl start docker
systemctl enable docker
```

验证安装：

```bash
docker --version
docker compose version
```

### 3. 调整系统参数（解决 iNotify 限制）

```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 4. 开放端口（如使用防火墙）

```bash
firewall-cmd --permanent --add-port=9000/tcp
firewall-cmd --reload
```

## 二、项目部署

### 1. 克隆项目

```bash
git clone https://github.com/your-org/maybe.git
cd maybe
```

### 2. 配置环境变量

```bash
cp .env.local.example .env.local
vi .env.local
```

`.env.local` 示例：

```env
SELF_HOSTED=false
SYNTH_API_KEY=your_api_key_here
EXCHANGE_RATE_PROVIDER=currency_api
```

### 3. 启动容器

```bash
docker compose -f .devcontainer/docker-compose.yml up -d --build
```

首次构建需要几分钟，等待所有容器状态变为 healthy：

```bash
docker compose -f .devcontainer/docker-compose.yml ps
```

### 4. 进入开发容器

```bash
docker compose -f .devcontainer/docker-compose.yml exec app bash
```

### 5. 安装依赖

```bash
bundle install
npm install
```

### 6. 初始化数据库

```bash
bundle exec rails db:setup
```

### 7. 启动开发服务器

```bash
bin/dev
```

app 容器的 command 是 sleep infinity，Rails 不会自动启动。每次容器重启后需要手动进去跑 bin/dev。
```bash
docker compose -f .devcontainer/docker-compose.yml exec app bash
rm -f tmp/pids/server.pid
bin/dev
```


浏览器访问 `http://your-server-ip:9000`。

## 三、日常开发流程

### 拉取最新代码

在宿主机项目目录下（不是容器里）：

```bash
git pull origin main
```

代码通过 volume 挂载，容器内自动同步，无需重建。

### 进入容器

```bash
docker compose -f .devcontainer/docker-compose.yml exec app bash
```

## 四、修改后如何重启验证

### 场景 1：修改了 Ruby/ERB/JS 代码

**不需要重启。** Rails 开发模式自动重载，保存文件后刷新浏览器即可。

> 例外：修改了 `config/initializers/` 下的文件需要重启 `bin/dev`。

### 场景 2：修改了环境变量（.env.local）

在容器内按 `Ctrl+C` 停掉 `bin/dev`，然后重新启动：

```bash
bin/dev
```

### 场景 3：修改了 Gemfile 或 package.json

```bash
# Ctrl+C 停掉 bin/dev
bundle install   # Gemfile 变更
npm install      # package.json 变更
bin/dev
```

### 场景 4：修改了 docker-compose.yml 或 Dockerfile

需要在宿主机上重建容器：

```bash
docker compose -f .devcontainer/docker-compose.yml down
docker compose -f .devcontainer/docker-compose.yml up -d --build
```

然后重新进入容器：

```bash
docker compose -f .devcontainer/docker-compose.yml exec app bash
bin/dev
```

### 场景 5：修改了数据库 migration

```bash
# 在容器内
bundle exec rails db:migrate
```

不需要重启 `bin/dev`。

## 五、常用命令速查

| 操作 | 命令 |
|------|------|
| 启动所有容器 | `docker compose -f .devcontainer/docker-compose.yml up -d` |
| 停止所有容器 | `docker compose -f .devcontainer/docker-compose.yml down` |
| 查看容器状态 | `docker compose -f .devcontainer/docker-compose.yml ps` |
| 查看日志 | `docker compose -f .devcontainer/docker-compose.yml logs -f web` |
| 进入开发容器 | `docker compose -f .devcontainer/docker-compose.yml exec app bash` |
| 启动开发服务器 | `bin/dev` |
| 初始化数据库 | `bundle exec rails db:setup` |
| 执行数据库迁移 | `bundle exec rails db:migrate` |
| 打开 Rails 控制台 | `bundle exec rails console` |
| 运行测试 | `bundle exec rails test` |
| 重建容器 | `docker compose -f .devcontainer/docker-compose.yml up -d --build` |

## 六、常见问题

### 端口被占用

修改 `.devcontainer/docker-compose.yml` 中的端口映射，外部端口改为未占用的端口，容器内部端口保持不变。

### PostgreSQL 版本不兼容

如果 `postgres:latest` 报数据格式错误，锁定版本为 `postgres:16`，并清除旧数据卷：

```bash
docker compose -f .devcontainer/docker-compose.yml down
docker volume rm devcontainer_postgres-data
docker compose -f .devcontainer/docker-compose.yml up -d
```

### Sidekiq Segfault（YJIT bug）

在 `docker-compose.yml` 的 worker 服务中添加环境变量：

```yaml
environment:
  RUBY_YJIT_ENABLE: "0"
```

### rails 命令找不到

使用 `bundle exec rails` 代替 `rails`。
