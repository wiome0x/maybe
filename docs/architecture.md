# Maybe 开源项目架构文档

## 技术栈概览

**后端**
- Ruby on Rails 7.2.2（Ruby 3.4.4）
- PostgreSQL（UUID 主键，自定义枚举，虚拟列）
- Puma Web 服务器

**前端**
- Hotwire（Turbo + Stimulus）实现 SPA 式交互，无需前端框架
- TailwindCSS v4.x，配合自定义设计系统（`app/assets/tailwind/maybe-design-system.css`）
- Propshaft 资产管道 + Importmap（无构建步骤）
- ViewComponent 组件库
- Lucide Icons 图标库

**异步任务**
- Sidekiq + Redis 后台任务队列
- Sidekiq-cron 定时任务
- 队列优先级：scheduled(10) > high_priority(4) > medium_priority(2) > low_priority(1) > default(1)

**监控与可观测性**
- Sentry — 错误追踪
- Logtail — 日志聚合
- Skylight — 生产环境性能监控
- Rack-mini-profiler — 开发环境性能分析

---

## 第三方 API 集成

| 厂商 | 用途 | 配置方式 | Provider 类 |
|------|------|----------|-------------|
| **Plaid** | 银行账户数据同步（交易、投资、负债） | `PLAID_CLIENT_ID` / `PLAID_SECRET`（美国）；`PLAID_EU_CLIENT_ID` / `PLAID_EU_SECRET`（欧洲） | `Provider::Plaid` |
| **Synth** | 汇率数据 + 证券价格（自研 API） | `SYNTH_API_KEY` 或 Settings 页面配置 | `Provider::Synth` |
| **Stripe** | 订阅支付、Checkout、Billing Portal | `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` | `Provider::Stripe` |
| **OpenAI** | AI 对话、交易自动分类、商家识别 | `OPENAI_ACCESS_TOKEN` 或 Settings 页面配置 | `Provider::Openai` |
| **Intercom** | 客户支持与站内消息 | `INTERCOM_APP_ID` / `INTERCOM_IDENTITY_VERIFICATION_KEY` | 直接集成 |
| **GitHub** | OAuth 集成 | 内置 | `Provider::Github` |
| **AWS S3 / Cloudflare R2** | 文件存储（头像、Logo、导入文件） | `ACTIVE_STORAGE_SERVICE` + 对应密钥 | Rails Active Storage |
| **SMTP（如 Resend）** | 邮件发送（密码重置、邮件确认） | `SMTP_ADDRESS` / `SMTP_PORT` 等 | ActionMailer |

---

## 数据提供者架构（Provider Registry Pattern）

```
Provider::Registry
  ├── :exchange_rates → Provider::Synth
  ├── :securities     → Provider::Synth
  └── :llm            → Provider::Openai

直接访问（非 concept）：
  ├── Provider::Plaid (us / eu)
  ├── Provider::Stripe
  └── Provider::Github
```

域模型通过 `Provided` concern 访问 Provider，调用方不感知具体 Provider 实现：

```ruby
ExchangeRate.find_or_fetch_rate(from: "USD", to: "CNY", date: Date.current)
```

---

## 认证与授权

- **Web 端**：基于 Session 的 Cookie 认证（`session_token`），支持 MFA（TOTP + 备用码）
- **API 端**：双重认证机制
  - OAuth2（Doorkeeper gem），支持 `read` / `read_write` scope，Token 有效期 1 年，支持 Refresh Token
  - API Key（`X-Api-Key` Header），加密存储，支持过期和撤销
- **限流**：Rack::Attack 中间件
  - OAuth Token 端点：10 次/分钟
  - API 请求：100 次/小时（托管模式）/ 10,000 次/小时（自托管模式）

---

## 运行模式

应用支持两种模式，通过 `SELF_HOSTED=true` 环境变量切换：

| 特性 | 托管模式（Managed） | 自托管模式（Self-Hosted） |
|------|---------------------|--------------------------|
| Stripe 支付 | ✅ | ❌ |
| Intercom 支持 | ✅ | ❌ |
| Plaid 集成 | ✅ | 可选配置 |
| Synth / OpenAI | ✅ | 可选配置 |
| API 限流 | 100 次/小时 | 10,000 次/小时 |
| 部署方式 | Maybe 团队托管 | Docker Compose |

---

## 部署架构

```
Docker Compose
├── app        (Rails + Puma, port 3000)
├── worker     (Sidekiq)
├── db         (PostgreSQL)
└── redis      (Redis, port 6379)
```

生产环境支持 Amazon S3 或 Cloudflare R2 作为文件存储后端。

---

## 核心域模型关系

```
Family
├── User (admin / member / super_admin)
├── Account (delegated type)
│   ├── Depository / Investment / Crypto / Property / Vehicle / OtherAsset
│   ├── CreditCard / Loan / OtherLiability
│   ├── Entry (delegated type)
│   │   ├── Transaction
│   │   ├── Valuation
│   │   └── Trade
│   ├── Balance (每日历史余额)
│   └── Holding (投资持仓)
└── PlaidItem → PlaidAccount → Account
```

---

## API 路由结构

```
/api/v1/
├── auth/signup, auth/login, auth/refresh
├── accounts (index)
├── transactions (CRUD)
├── chats + messages (AI 对话)
└── usage (API 用量)

/webhooks/
├── plaid, plaid_eu
└── stripe

/oauth/  (Doorkeeper OAuth2 标准端点)
```

---

## 后台任务

| Job | 用途 | 队列 |
|-----|------|------|
| `SyncJob` | 数据同步编排 | high_priority |
| `ImportMarketDataJob` | 定时市场数据更新 | scheduled |
| `AutoCategorizeJob` | AI 交易自动分类 | default |
| `AutoDetectMerchantsJob` | AI 商家识别 | default |
| `AssistantResponseJob` | AI 对话响应 | default |
| `StripeEventHandlerJob` | Stripe Webhook 处理 | default |
| `ImportJob` | CSV 文件导入 | default |
| `FamilyDataExportJob` | 数据导出 | default |
| `UserPurgeJob` | 用户账户删除 | default |
| `SyncCleanerJob` | 清理旧同步记录 | low_priority |

---

## 同步机制（Sync）

应用通过 `Syncable` concern 实现数据同步：

- **Family Sync**：每日自动触发，编排所有子同步
- **PlaidItem Sync**：ETL 流程 — 从 Plaid API 拉取数据 → 存储到 PlaidAccount → 转换到内部 Account/Entry 模型
- **Account Sync**：计算每日余额、持仓、自动匹配转账、数据增强

每次 Entry 更新都会触发对应 Account 的重新同步。

---

## 关键文件索引

| 类别 | 文件路径 |
|------|----------|
| 核心模型 | `app/models/user.rb`, `family.rb`, `account.rb`, `entry.rb` |
| Provider | `app/models/provider/registry.rb`, `synth.rb`, `plaid.rb`, `stripe.rb`, `openai.rb` |
| API 控制器 | `app/controllers/api/v1/base_controller.rb`, `auth_controller.rb` |
| 路由 | `config/routes.rb` |
| 数据库 | `config/database.yml`, `db/schema.rb` |
| 认证 | `config/initializers/doorkeeper.rb`, `rack_attack.rb` |
| 部署 | `Dockerfile`, `.devcontainer/docker-compose.yml` |
| 依赖 | `Gemfile`, `package.json` |
