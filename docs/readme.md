## 开发功能列表
基础的中文语言支持
数据导入（CSV导入，与同步）
汇率与汇率计算





## 正在进行

1、修复中文显示问题 √
2、AI功能 新增 Openrouter 的支持 √
3、实现盈透活动报表的导入功能 √
4、盈透API的支持
5、币安的支持
6、使用开源汇率日更新 √





















## QA

### plaid api 都需要那些权限

  
#### 需要申请的 3 个产品

在 [Plaid Dashboard](https://dashboard.plaid.com/overview) → Product Access 页面，申请以下产品：

| 产品 | Plaid 名称 | 分类 | 说明 |
|------|-----------|------|------|
| **Transactions** | `transactions` | Financial Management | 银行交易记录，最多 24 个月历史数据 |
| **Investments** | `investments` | Financial Management | 券商持仓和投资交易（Fidelity、Schwab 等） |
| **Liabilities** | `liabilities` | Financial Management | 信用卡、贷款、房贷负债信息 |

三个都在 `financial_management` 解决方案下，申请时选这个分类。

#### 申请步骤

1. 登录 [https://dashboard.plaid.com](https://dashboard.plaid.com)
2. 左侧菜单 → Product Access（或 Request Access）
3. Solution 选 `Financial Management`
4. 勾选 `Transactions`、`Investments`、`Liabilities`
5. 填写用途说明，比如："Personal finance management app for tracking accounts, investments, and debts"
6. 提交

## 可选但推荐

| 产品 | 说明 |
|------|------|
| `transactions_refresh` | 按需刷新交易数据（Transactions 的附加功能） |
| `investments_refresh` | 按需刷新投资数据（Investments 的附加功能） |

这两个 refresh 产品让你可以主动触发数据更新，而不是等 Plaid 的定时推送。

---

Sandbox 环境不需要审批就能测试所有产品。申请主要是为了 Development 和 Production 环境。