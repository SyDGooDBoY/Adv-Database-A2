# Member 5 表结构中文说明（KYC/AML 异常与报表）

本文档配套 `09_add_chinese_comments.sql`，用大白话说明 **Member 5 模块涉及的表和字段分别是什么、用来干什么**。执行过注释脚本后，你在 CloudBeaver / pgAdmin 里打开这些表和字段，也能直接看到一样的中文说明。

---

## 一、这个模块在做什么（一句话版）

银行有 CRM、贷款、AML/KYC 三个系统，同一个客户在里面是不同编号。**Member 5 负责"合规检查"这一段**：客户的 KYC 验证资料齐不齐、有没有过期，反洗钱筛查有没有命中名单；一旦发现问题就**开一个案件**跟进，最后把"哪些异常、挂了多久、结没结"做成监管报表。

数据流向：

```
Bronze 原始记录  →  Silver 事件表（验证/筛查）  →  Silver 案件表（人工跟进）  →  Gold 异常事实表（报表）
   raw_kyc_verification        kyc_verification_record      special_verification_case     fact_compliance_exception
   raw_aml_screening           aml_screening_result         aml_case
```

---

## 二、表清单速查（先看这张表就够）

| 层 | 表名 | 中文名 | 一行代表什么 | 行数含义 |
|---|---|---|---|---|
| Silver | `kyc_verification_record` | KYC 验证事件表 | 客户**做了一次**身份验证 | 事件流水，同一客户会有多行 |
| Silver | `special_verification_case` | 验证案件表 | **一个需要跟进的 KYC 问题** | 案件，同一问题只有一行 |
| Silver | `aml_screening_result` | AML 筛查事件表 | 客户**被名单库筛了一次** | 事件流水，同一客户会有多行 |
| Silver | `aml_case` | AML 调查案件表 | **一次反洗钱调查** | 案件，一次异常只有一行 |
| Gold | `fact_compliance_exception` | 合规异常事实表 | **一笔异常（报表用）** | 一个来源案件一行，累积更新 |

**事件表 vs 案件表的关键区别**（这是本模块设计的核心）：

- **事件表**记流水，来一条记一条，永不覆盖。客户做了 3 次验证就有 3 行。
- **案件表**记问题，同一个问题只保留一行，重复发现会**复用**已有案件而不是再开一个。这样不会出现"同一个毛病报了 20 个案件"。

---

## 三、逐表逐字段说明

### 3.1 `silver.kyc_verification_record` — KYC 验证事件表

> 一行 = 某个客户在某天做了一次什么类型的验证、结果如何。

| 字段 | 中文含义 | 备注 |
|---|---|---|
| `kyc_verification_id` | **主键**。验证事件编号 | 由"来源系统 + 来源编号"算出来，重跑不会变，所以不会重复插入 |
| `customer_id` | 已合并的**金客户**编号 | 为空说明身份还没合并完成，靠下一列定位 |
| `source_customer_record_id` | **来源客户记录**编号 | 指向来源系统里的原始客户记录 |
| `source_system_id` | 来源系统 | 本模块都是 `AMLKYC` |
| `reviewed_by` | 审核人 | 可选。缺证件的记录不该填审核人 |
| `source_kyc_reference` | 来源系统的验证编号 | 如 `VFY-004`，用于跟源数据对账 |
| `verification_type` | 验证类型 | 身份证件 / 地址验证 / 资金来源 / 强化尽调 / 定期复核 |
| `verification_status` | 验证结果 | 已通过 / 待处理 / **缺证件** / 失败 / 已过期 |
| `verification_date` | 验证发生时间 | |
| `expiry_date` | 有效期截止日 | **判断这次验证还能不能复用**，就是拿它跟报告基准日比 |
| `risk_level_at_verification` | 验证当时的风险等级 | 历史快照，不会跟着客户后来的风险变化而变 |

**哪些情况会变成异常？** 缺证件/待处理/失败 → `KYC_GAP`（资料缺口）；已过有效期 → `STATUS_DISCREPANCY`（状态矛盾）。

---

### 3.2 `silver.special_verification_case` — 验证案件表

> 一行 = 一个需要人工跟进的 KYC 问题。

| 字段 | 中文含义 | 备注 |
|---|---|---|
| `verification_case_id` | **主键**。案件编号 | 同一验证事件 + 同一问题类型只生成一个，保证复用 |
| `customer_id` | 涉及的金客户 | 可为空（身份未确认） |
| `source_customer_record_id` | 涉及的来源客户记录 | 身份未合并时靠它锁定当事人 |
| `match_id` | 关联的客户匹配记录 | 用于"匹配存疑"类案件 |
| `kyc_verification_id` | **触发本案件的验证事件** | 指向 `kyc_verification_record` |
| `assigned_user_id` | 案件处理人 | 可为空（还没派人） |
| `case_type` | **案件类型（三种之一）** | `KYC_GAP` 资料缺失 / `IDENTITY_MISMATCH` 身份对不上 / `STATUS_DISCREPANCY` 状态自相矛盾 |
| `trigger_type` | 触发来源类别 | 由金客户触发 / 由来源客户记录触发 |
| `case_reason` | 立案原因 | 格式"规则名: 问题描述"，看一眼就知道为什么开案 |
| `case_status` | 案件状态 | 待处理 / 处理中 / 已解决 / 已关闭 |
| `severity` | 严重程度 | 低 / 中 / 高 / 紧急 |
| `opened_at` | 立案时间 | 取**业务时间**而非脚本运行时间，重跑不会让账龄凭空变大 |
| `resolved_at` | 解决时间 | 只有"已解决/已关闭"才有值 |
| `resolution_outcome` | 解决结论 | 说明凭什么判定已清除 |

---

### 3.3 `silver.aml_screening_result` — AML 筛查事件表

> 一行 = 某个客户在某天被名单库筛了一次、命中程度如何。

| 字段 | 中文含义 | 备注 |
|---|---|---|
| `aml_screening_id` | **主键**。筛查事件编号 | 同样由来源编号算出，可重复执行 |
| `customer_id` | 被筛查的金客户 | 可为空 |
| `source_customer_record_id` | 被筛查的来源客户记录 | |
| `source_system_id` | 来源系统 | `AMLKYC` |
| `source_screening_reference` | 来源系统的筛查编号 | 如 `SCR-005-2` |
| `screening_type` | 名单类别 | 制裁名单 / 政要(PEP) / 监控名单 / 负面新闻 |
| `screening_date` | 筛查发生时间 | |
| `screening_result` | 筛查结论 | 未命中 / **疑似命中** / 确认命中 / 误报 |
| `match_score` | 相似度得分 | 0 到 1，越高越像名单上的人。**是依据不是结论** |
| `provider_reference` | 外部服务商流水号 | 便于追查原始结果 |
| `review_required_flag` | 是否需要人工复核 | 命中类结论必须为真，否则算源系统漏标 |

> **重要业务含义**：命中名单只是"疑似"，**不等于确认有问题**。所以它只触发"案件复核"，不会直接把客户定性。

---

### 3.4 `silver.aml_case` — AML 调查案件表

> 一行 = 一次反洗钱调查。可以由筛查命中触发，也可以由其他有据可查的信号触发。

| 字段 | 中文含义 | 备注 |
|---|---|---|
| `aml_case_id` | **主键**。案件编号 | 同一筛查事件 + 同一类型只建一次 |
| `customer_id` | 涉及的金客户 | 可为空 |
| `source_customer_record_id` | 涉及的来源客户记录 | |
| `aml_screening_id` | **触发的筛查事件** | 允许为空（案件来自其他信号时） |
| `assigned_user_id` | 调查负责人 | 可为空 |
| `trigger_type` | 触发来源类别 | 制裁筛查 / 政要筛查 / 监控名单筛查 / 负面新闻筛查 / 其他警报 |
| `trigger_reference` | 触发依据的文字引用 | 格式"规则名: 来源客户编号" |
| `case_type` | 案件类型 | 本模块固定用 `AML_SCREENING_REVIEW`（**警报复核**），强调是复核不是定性 |
| `case_status` | 案件状态 | 待处理 / 调查中 / 已结案 |
| `risk_level` | 风险等级 | 低 / 中 / 高 / 紧急 |
| `opened_at` | 立案时间 | 取触发筛查的业务时间 |
| `closed_at` | 结案时间 | 只有"已结案"才有值 |
| `case_outcome` | 结案结论 | 复核结果与不再跟进的理由 |

---

### 3.5 `gold.fact_compliance_exception` — 合规异常事实表（报表数据源）

> 一行 = **一笔异常**。这是**累积型**事实表：案件没结时，每次刷新**更新同一行**，不新增行，所以能真实反映"这笔异常挂了多久"。

| 字段 | 中文含义 | 备注 |
|---|---|---|
| `exception_fact_id` | **主键**。异常编号 | 由"来源类型 + 案件编号"算出，刷新时能精确命中同一行 |
| `customer_key` | 数仓客户代理键 | 指向 `dim_customer`。身份未确认时为 NULL，之后自动补上 |
| `verification_case_id` | 来源为验证案件时的案件号 | 来源是 AML 时**必须为空** |
| `aml_case_id` | 来源为 AML 案件时的案件号 | 来源是验证时**必须为空** |
| `exception_source_type` | 异常来源类型 | `VERIFICATION`（KYC 类）/ `AML`（反洗钱类） |
| `exception_type` | 异常类型 | 继承案件类型，如 `KYC_GAP`、`STATUS_DISCREPANCY`、`AML_SCREENING_REVIEW` |
| `exception_status` | 异常状态 | 未结 / 处理中 / 已解决 / 已关闭 |
| `severity` | 严重程度 | 低 / 中 / 高 / 紧急 |
| `opened_date` | 开案日期 | 账龄计算起点 |
| `resolved_date` | 结案日期 | 未结案为 NULL |
| `as_of_date` | **报告基准日** | 数据截止到哪天；未结案件账龄算到这一天 |
| `days_open` | **已挂天数（账龄）** | = 结案日（或基准日）− 开案日，且**不会超过基准日** |
| `last_updated_at` | 本行最后刷新时间 | 用于确认数据新鲜度 |

> **两条必须记住的规则**：① 两个案件号**必有且仅有一个**，且与来源类型一致；② 每个来源案件在全表**只出现一次**。

---

## 四、本模块创建的视图（报表直接查这些）

| 视图 | 中文名 | 用途 |
|---|---|---|
| `gold.vw_kyc_aml_exception_report` | **异常报表主视图** | 一行一笔异常，并带出立案原因、关联事件、结案结论。身份未确认的异常**也会保留**，不会被过滤掉 |
| `gold.vw_compliance_exception_summary` | 异常汇总视图 | 按客户+来源+类型统计：异常总数、未结数、已结数、最长账龄、最高严重程度 |
| `silver.vw_kyc_aml_exception_lineage` | **数据血缘视图** | 把"原始记录 → 发布事件 → 案件 → 报表异常"串成一条链，用于向审计解释结论怎么来的 |

> 汇总视图里的"最高严重程度"是按 **紧急 > 高 > 中 > 低** 的显式排序取的，不是按字母排序（按字母会算出"中"比"高"严重，那就错了）。

---

## 五、与其他成员表的衔接关系（重要）

本模块**只注释自己拥有的对象**，不去改别人的表，避免覆盖组员的注释。以下是衔接点：

| 表 | 归属 | 本模块如何使用 |
|---|---|---|
| `bronze.raw_kyc_verification`、`bronze.raw_aml_screening` | Member 1 | **只读**。本模块从中读取原始记录，绝不修改 |
| `bronze.raw_aml_kyc_customer` | Member 1 | **只读**。从这取客户姓名等属性来建立身份 |
| `silver.customer_master`、`silver.source_customer_record` | Member 2 | 复用已有身份；**只在本模块事件引用的身份尚不存在时**才补建，绝不改写已解析好的身份 |
| `silver.data_quality_issue` | 共享（Member 6） | 本模块只**写入**自己发现的问题，并为 KYC 类问题回填案件号 |
| `silver.data_lineage_record` | 共享 | 本模块只**写入**自己发布事件的血缘记录 |
| `gold.dim_customer` | Member 4 | **只读**，用来给异常补上客户代理键 |

---

## 六、怎么在数据库里看这些中文注释

**CloudBeaver / DBeaver**：展开表 → 看 Columns 面板的 Comment 列；表本身的注释在表的属性里。

**用 SQL 查**：

```sql
-- 查某张表所有字段的中文注释
SELECT
  c.ordinal_position AS 序号,
  c.column_name      AS 字段名,
  c.data_type        AS 类型,
  col_description('silver.kyc_verification_record'::regclass, c.ordinal_position) AS 中文说明
FROM information_schema.columns c
WHERE c.table_schema = 'silver'
  AND c.table_name = 'kyc_verification_record'
ORDER BY c.ordinal_position;

-- 一次查出本模块五张表各自的表注释
SELECT
  c.relname                        AS 表名,
  obj_description(c.oid)           AS 中文说明
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE (n.nspname, c.relname) IN (
  ('silver', 'kyc_verification_record'),
  ('silver', 'special_verification_case'),
  ('silver', 'aml_screening_result'),
  ('silver', 'aml_case'),
  ('gold',   'fact_compliance_exception')
);
```

---

## 七、注释脚本本身做了什么

`09_add_chinese_comments.sql` 一次执行，给下面这些对象补中文注释：

| 对象类别 | 数量 | 说明 |
|---|---|---|
| 表 | 5 | 4 张 Silver 表 + 1 张 Gold 事实表 |
| 字段 | 62 | 五张表的**每一列**都有 |
| 视图 | 3 | 报表主视图、汇总视图、血缘视图 |
| 函数 | 10 | 标识生成、规则检测、案件查找/建立等 |
| 过程 | 7 | 批次装载、案件发布与推进、事实刷新 |

几个要点：

1. **用的是 PostgreSQL 语法** `COMMENT ON ... IS '...'`，不是 MySQL 的 `COMMENT` 关键字。
2. **注释是覆盖而不是追加**：每个对象只能有一条注释，所以执行后数据库里显示的是中文（原来脚本里的英文注释被替换掉了）。
3. **可以随便重复执行**，`COMMENT ON` 天然幂等，不会报错也不会重复添加。
4. 执行顺序：在 `00`–`07` 建完对象之后执行，之后任何时间再跑一遍都行。
