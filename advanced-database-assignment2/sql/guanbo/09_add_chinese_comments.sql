-- PostgreSQL 15+
-- Member 5：把本模块拥有的全部数据库对象补上中文注释。
--
-- 说明：
--   1. PostgreSQL 用 COMMENT ON ... IS '...' 给对象加注释，不是 MySQL 的
--      COMMENT 关键字。对象注释会被"覆盖"而不是追加，所以本脚本执行后，
--      这些对象在数据库里显示的就是中文说明。
--   2. 本脚本只覆盖 Member 5 自己拥有并对外发布的对象，不碰其他成员的表，
--      避免覆盖别人的注释。
--   3. 可以重复执行：COMMENT ON 是幂等的。
--
-- 执行顺序：在 00-07 全部建完之后执行，任何时间重复执行都可以。

-- ============================================================================
-- 一、Silver 层：KYC 验证事件与验证案件
-- ============================================================================

COMMENT ON TABLE silver.kyc_verification_record IS
  'KYC 验证事件表。一行代表"某个客户在某天做了一次什么类型的验证、结果如何"，是事件流水而不是客户的固定属性，所以同一个客户可以有多条。业务主键是"来源系统 + 来源 KYC 编号"，重复导入不会产生重复行。每条记录至少要能指向一个客户身份（已合并的金客户或尚未合并的来源客户记录），两者都填时必须指向同一个人。本表是 Member 5 所有合规异常判定的数据基础。';

COMMENT ON COLUMN silver.kyc_verification_record.kyc_verification_id IS
  '本表主键。由"来源系统 + 来源 KYC 编号"用 MD5 稳定生成，因此重复处理同一批数据会得到同一个编号，不会重复插入。';

COMMENT ON COLUMN silver.kyc_verification_record.customer_id IS
  '已成功合并后的金客户编号，关联 silver.customer_master。为空表示这个客户的身份还没合并完成，此时必须靠 source_customer_record_id 定位。';

COMMENT ON COLUMN silver.kyc_verification_record.source_customer_record_id IS
  '来源客户记录编号，关联 silver.source_customer_record，代表"这条验证是针对来源系统里哪一条客户记录做的"。';

COMMENT ON COLUMN silver.kyc_verification_record.source_system_id IS
  '来源系统编号。本模块的数据都来自 AML/KYC 系统（AMLKYC）。';

COMMENT ON COLUMN silver.kyc_verification_record.reviewed_by IS
  '审核人，关联 silver.user_account。可选字段；验证通过时才可能有值，缺失证件的记录不应填审核人。';

COMMENT ON COLUMN silver.kyc_verification_record.source_kyc_reference IS
  '来源系统里的 KYC 事件编号（如 VFY-004），加来源系统后唯一，用于跟源数据对账。';

COMMENT ON COLUMN silver.kyc_verification_record.verification_type IS
  '验证类型：IDENTITY_DOCUMENT 身份证件、ADDRESS_VERIFICATION 地址验证、SOURCE_OF_FUNDS 资金来源、ENHANCED_DUE_DILIGENCE 强化尽调、PERIODIC_REVIEW 定期复核。';

COMMENT ON COLUMN silver.kyc_verification_record.verification_status IS
  '验证结果状态：VERIFIED 已通过、PENDING 待处理、MISSING_DOCUMENT 缺证件、FAILED 失败、EXPIRED 已过期。其中缺证件/待处理/失败属于"信息不完整"，会生成 KYC_GAP 异常。';

COMMENT ON COLUMN silver.kyc_verification_record.verification_date IS
  '本次验证发生的业务时间。';

COMMENT ON COLUMN silver.kyc_verification_record.expiry_date IS
  '验证结果的有效期截止日。判断"这次验证还能不能复用"就是拿它跟报告基准日比较：晚于基准日才算仍然有效。为空表示不设有效期。';

COMMENT ON COLUMN silver.kyc_verification_record.risk_level_at_verification IS
  '做这次验证时的风险等级（LOW/MEDIUM/HIGH 等）。这是当时快照，不会随后续风险变化而变。';

COMMENT ON TABLE silver.special_verification_case IS
  '验证案件表（合规调查案件）。一行代表"一个需要人工跟进的 KYC 问题"，是案件而不是事件：同一个验证事件只对应一个案件，但一个案件可以串联起该事件的多次发现。案件类型严格限定为 KYC_GAP（信息不全）、IDENTITY_MISMATCH（身份对不上）、STATUS_DISCREPANCY（状态自相矛盾）三种，这正是报告要求的报告口径。案件必须至少有一个主体或触发引用（客户、来源记录、匹配记录、验证事件四者之一），允许身份尚未确认时先建案。';

COMMENT ON COLUMN silver.special_verification_case.verification_case_id IS
  '本表主键。由"触发的验证事件 + 案件类型"稳定生成，所以同一问题重复检测会复用同一个案件，不会重复建案。';

COMMENT ON COLUMN silver.special_verification_case.customer_id IS
  '案件涉及的金客户编号，关联 silver.customer_master。可为空，表示身份尚未确认。';

COMMENT ON COLUMN silver.special_verification_case.source_customer_record_id IS
  '案件涉及的来源客户记录编号，关联 silver.source_customer_record。身份未合并时靠它锁定当事人。';

COMMENT ON COLUMN silver.special_verification_case.match_id IS
  '关联的客户匹配记录编号，关联 silver.customer_source_match，用于"匹配存疑"类案件。';

COMMENT ON COLUMN silver.special_verification_case.kyc_verification_id IS
  '触发本案件的 KYC 验证事件编号，关联 silver.kyc_verification_record。';

COMMENT ON COLUMN silver.special_verification_case.assigned_user_id IS
  '案件处理人，关联 silver.user_account。可为空（尚未指派）。';

COMMENT ON COLUMN silver.special_verification_case.case_type IS
  '案件类型，只允许三种：KYC_GAP 资料缺失、IDENTITY_MISMATCH 身份不匹配、STATUS_DISCREPANCY 状态矛盾。与报告要求一一对应。';

COMMENT ON COLUMN silver.special_verification_case.trigger_type IS
  '触发来源类别：GOLDEN_CUSTOMER 由已合并客户触发、SOURCE_CUSTOMER_RECORD 由来源客户记录触发。用于说明这条案件是凭什么建立的。';

COMMENT ON COLUMN silver.special_verification_case.case_reason IS
  '立案原因，格式为"规则名: 问题描述"，最长 1000 字符。人看这一列就知道为什么开案。';

COMMENT ON COLUMN silver.special_verification_case.case_status IS
  '案件状态：OPEN 待处理、IN_REVIEW 处理中、RESOLVED 已解决、CLOSED 已关闭。状态与 resolved_at 必须一致（已解决必须有解决时间，处理中不能有）。';

COMMENT ON COLUMN silver.special_verification_case.severity IS
  '严重程度：LOW 低、MEDIUM 中、HIGH 高、CRITICAL 紧急。由检测规则的级别映射而来。';

COMMENT ON COLUMN silver.special_verification_case.opened_at IS
  '立案时间。取触发事件的业务时间，而不是脚本运行时间，这样重新跑脚本不会让账龄凭空变大。';

COMMENT ON COLUMN silver.special_verification_case.resolved_at IS
  '解决时间。仅当状态为 RESOLVED 或 CLOSED 时才有值。';

COMMENT ON COLUMN silver.special_verification_case.resolution_outcome IS
  '解决结论。说明这条案件是因为什么被判定为已清除的。';

-- ============================================================================
-- 二、Silver 层：AML 筛查事件与 AML 案件
-- ============================================================================

COMMENT ON TABLE silver.aml_screening_result IS
  'AML 反洗钱筛查事件表。一行代表"某个客户在某天被名单库筛查了一次、命中程度如何"，同样是事件流水，同一客户可有多条。业务主键是"来源系统 + 来源筛查编号"。关键业务含义：筛查命中（POTENTIAL_MATCH 等）只是"疑似"，不等于确认有问题，所以它只触发案件复核，不直接定性。';

COMMENT ON COLUMN silver.aml_screening_result.aml_screening_id IS
  '本表主键。由"来源系统 + 来源筛查编号"用 MD5 稳定生成，重复处理不会重复插入。';

COMMENT ON COLUMN silver.aml_screening_result.customer_id IS
  '被筛查的金客户编号，关联 silver.customer_master。可为空（身份未合并）。';

COMMENT ON COLUMN silver.aml_screening_result.source_customer_record_id IS
  '被筛查的来源客户记录编号，关联 silver.source_customer_record。';

COMMENT ON COLUMN silver.aml_screening_result.source_system_id IS
  '来源系统编号。本模块的数据来自 AML/KYC 系统（AMLKYC）。';

COMMENT ON COLUMN silver.aml_screening_result.source_screening_reference IS
  '来源系统里的筛查事件编号（如 SCR-005-2），加来源系统后唯一，用于跟源数据对账。';

COMMENT ON COLUMN silver.aml_screening_result.screening_type IS
  '筛查名单类别：SANCTIONS 制裁名单、PEP 政治公众人物、WATCHLIST 监控名单、ADVERSE_MEDIA 负面新闻。';

COMMENT ON COLUMN silver.aml_screening_result.screening_date IS
  '本次筛查发生的业务时间。';

COMMENT ON COLUMN silver.aml_screening_result.screening_result IS
  '筛查结论：CLEAR 未命中、POTENTIAL_MATCH 疑似命中、CONFIRMED_MATCH 确认命中、FALSE_POSITIVE 误报。前两者属于"警报"，必须进入复核。';

COMMENT ON COLUMN silver.aml_screening_result.match_score IS
  '与名单的相似度得分，取值 0.0000 到 1.0000。分数越高越接近名单人员；它是判定依据而不是最终结论。';

COMMENT ON COLUMN silver.aml_screening_result.provider_reference IS
  '外部筛查服务商返回的流水号，用于向供应商追查原始结果。';

COMMENT ON COLUMN silver.aml_screening_result.review_required_flag IS
  '是否需要人工复核。凡是警报类结论都必须为真；如果为假，说明源系统漏标了复核要求，会生成 STATUS_DISCREPANCY 异常。';

COMMENT ON TABLE silver.aml_case IS
  'AML 调查案件表。一行代表"一次针对洗钱/制裁风险的调查"，可以由一次筛查命中触发，也可以由其他有据可查的信号触发（所以筛查引用允许为空）。与验证案件分表存放，是为了不让"疑似命中"被当成"已确认问题"。必须至少有一个主体或触发依据（客户、来源记录、筛查事件、触发引用四者之一）；状态为 CLOSED 时必须有结案时间。';

COMMENT ON COLUMN silver.aml_case.aml_case_id IS
  '本表主键。由"触发的筛查事件 + 案件类型"稳定生成，重复检测会复用同一案件。';

COMMENT ON COLUMN silver.aml_case.customer_id IS
  '案件涉及的金客户编号，关联 silver.customer_master。可为空（身份未合并）。';

COMMENT ON COLUMN silver.aml_case.source_customer_record_id IS
  '案件涉及的来源客户记录编号，关联 silver.source_customer_record。';

COMMENT ON COLUMN silver.aml_case.aml_screening_id IS
  '触发本案件的筛查事件编号，关联 silver.aml_screening_result。允许为空，表示案件来自其他信号。';

COMMENT ON COLUMN silver.aml_case.assigned_user_id IS
  '调查负责人，关联 silver.user_account。可为空。';

COMMENT ON COLUMN silver.aml_case.trigger_type IS
  '触发来源类别：SANCTIONS_SCREENING 制裁筛查、PEP_SCREENING 政要筛查、WATCHLIST_SCREENING 监控名单筛查、ADVERSE_MEDIA_SCREENING 负面新闻筛查、SCREENING_ALERT 其他筛查警报。';

COMMENT ON COLUMN silver.aml_case.trigger_reference IS
  '触发依据的文字引用，格式为"规则名: 来源客户编号"，便于人工回溯这条案件是凭什么开的。';

COMMENT ON COLUMN silver.aml_case.case_type IS
  '案件类型。本模块固定使用 AML_SCREENING_REVIEW（筛查警报复核），强调这是复核而不是定性结论。';

COMMENT ON COLUMN silver.aml_case.case_status IS
  '案件状态：OPEN 待处理、IN_REVIEW 调查中、CLOSED 已结案。已结案必须有 closed_at，未结案不能有。';

COMMENT ON COLUMN silver.aml_case.risk_level IS
  '案件风险等级：LOW/MEDIUM/HIGH/CRITICAL。由检测规则级别映射而来。';

COMMENT ON COLUMN silver.aml_case.opened_at IS
  '立案时间。取触发筛查的业务时间，保证重跑脚本不改变账龄。';

COMMENT ON COLUMN silver.aml_case.closed_at IS
  '结案时间。仅当状态为 CLOSED 时才有值。';

COMMENT ON COLUMN silver.aml_case.case_outcome IS
  '结案结论。说明复核结果，以及为什么不再需要跟进。';

-- ============================================================================
-- 三、Gold 层：合规异常累积快照事实表
-- ============================================================================

COMMENT ON TABLE gold.fact_compliance_exception IS
  '合规异常累积快照事实表（KYC/AML 异常报表的数据源）。一行代表"一个来源案件"，是累积型事实：案件未结案时每次刷新都更新同一行，而不是新增一行，所以它能真实反映"这笔异常已经挂了多久"。规则要求 verification_case_id 与 aml_case_id 二者必有且仅有一个，并且要与 exception_source_type 一致；每个来源案件在全表只出现一次。customer_key 在身份未确认时允许为空，报表用左连接保留这些行而不是丢掉。';

COMMENT ON COLUMN gold.fact_compliance_exception.exception_fact_id IS
  '事实表主键。由"来源类型 + 来源案件编号"稳定生成，因此刷新时能精确命中同一行做更新。';

COMMENT ON COLUMN gold.fact_compliance_exception.customer_key IS
  '关联 gold.dim_customer 的代理键（数仓维度外键，不是业务编号）。身份尚未确认时为 NULL，一旦维度表有了该客户的当前版本就会自动补上。';

COMMENT ON COLUMN gold.fact_compliance_exception.verification_case_id IS
  '来源为验证案件时的案件编号，关联 silver.special_verification_case。来源类型为 AML 时本列必须为空。';

COMMENT ON COLUMN gold.fact_compliance_exception.aml_case_id IS
  '来源为 AML 案件时的案件编号，关联 silver.aml_case。来源类型为 VERIFICATION 时本列必须为空。';

COMMENT ON COLUMN gold.fact_compliance_exception.exception_source_type IS
  '异常来源类型：VERIFICATION 来自 KYC 验证案件、AML 来自反洗钱调查案件。用于让报表按来源分类汇总。';

COMMENT ON COLUMN gold.fact_compliance_exception.exception_type IS
  '异常类型，直接继承来源案件类型，例如 KYC_GAP、STATUS_DISCREPANCY、AML_SCREENING_REVIEW。报表的核心分类维度。';

COMMENT ON COLUMN gold.fact_compliance_exception.exception_status IS
  '异常状态：OPEN 未结、IN_REVIEW 处理中、RESOLVED 已解决、CLOSED 已关闭。由案件状态映射而来，是事实表自己对案件的看法。';

COMMENT ON COLUMN gold.fact_compliance_exception.severity IS
  '严重程度：LOW/MEDIUM/HIGH/CRITICAL。继承自来源案件，用于报表排序与汇总时取最高级别。';

COMMENT ON COLUMN gold.fact_compliance_exception.opened_date IS
  '开案日期（取案件立案时间的日期部分），是计算账龄的起点。';

COMMENT ON COLUMN gold.fact_compliance_exception.resolved_date IS
  '结案日期。未结案时为 NULL。注意：账龄计算时会把结案日按报告基准日封顶，避免出现"比报告期还久"的异常。';

COMMENT ON COLUMN gold.fact_compliance_exception.as_of_date IS
  '本行数据的报告基准日（数据截止到哪天）。报表按它筛选，未结案件的账龄也算到这一天。';

COMMENT ON COLUMN gold.fact_compliance_exception.days_open IS
  '异常已挂天数 = 结案日（或未结案时的报告基准日）减去开案日，且不会超过报告基准日。报表的账龄列。';

COMMENT ON COLUMN gold.fact_compliance_exception.last_updated_at IS
  '本行最后一次刷新的时间。用于确认数据新鲜度，以及判断未结案件是否被更新过。';

-- ============================================================================
-- 四、本模块创建的视图
-- ============================================================================

COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'KYC/AML 异常报表主视图：一行一笔合规异常，并把来源案件的关键信息（触发类型、立案原因、关联验证事件或筛查事件、结案结论）一起带出来。身份未确认的异常通过左连接保留，不会被过滤掉，符合"未解决身份也要出现在监管报表里"的要求。';

COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  '合规异常汇总视图：按客户 + 异常来源 + 异常类型聚合，给出异常总数、未结数、已结数、最长挂账天数与最高严重程度。供报表的汇总区块直接使用。注意最高严重程度是按 CRITICAL > HIGH > MEDIUM > LOW 的显式排序取的，不是按字母排序。';

COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  '合规异常数据血缘视图：把"Bronze 原始记录 → Silver 发布事件 → 合规案件 → Gold 异常事实"串成一条可追溯链路。用于向审计说明每个异常结论是怎么来的。';

-- ============================================================================
-- 五、本模块创建的标识生成函数
-- ============================================================================

COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  '根据"来源系统 + 来源 KYC 编号"生成稳定的 KYC 验证事件主键。用途是让案件处理步骤可以只用业务编号就定位到已发布事件，不必回查数据库；同时保证重复处理得到同一个编号。';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  '根据"来源系统 + 来源筛查编号"生成稳定的 AML 筛查事件主键，作用与 KYC 版本相同。';

COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  '根据"来源类型 + 来源案件编号"生成异常事实表主键，保证同一个案件永远对应同一行事实，从而实现"刷新而非新增"。';

-- ============================================================================
-- 六、本模块创建的装载过程
-- ============================================================================

COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  '为 KYC/AML 事件建立最小的客户身份：先按"来源系统 + 来源客户编号"建立来源客户记录，再为客户建立金客户记录与匹配关系。关键约束是绝不修改其他成员已经解析好的身份，只补齐本模块事件所引用的、尚不存在的那些。客户姓名等属性取自 AML/KYC 源系统的客户数据。';

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  '把一个批次的 Bronze KYC 验证原始数据校验后发布到 Silver。校验中属于"阻断级"的问题会让该条事件不予发布并在数据质量问题表留痕；其余问题照常发布，交由后续步骤生成案件。可重复执行，重复执行不会产生重复行。';

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  '把一个批次的 Bronze AML 筛查原始数据校验后发布到 Silver，处理逻辑与 KYC 版本一致。';

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Member 5 的批次总入口：建立客户身份 → 发布 KYC 与 AML 事件到 Silver → 执行全部校验规则并登记数据质量问题。它以参数带入报告基准日，用于判定验证结果是否过期。';

-- ============================================================================
-- 七、本模块创建的校验函数
-- ============================================================================

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'KYC 验证规则的检测函数：对指定批次的每条事件套用全部 KYC 规则，并只返回该记录最严重的那一条发现（按规则优先级、严重程度、规则名依次排序取第一条），保证一条记录不会重复报多个问题。批次参数传 NULL 表示检查全部批次，此时每笔事件取 Bronze 中最新的一版，用于判断历史问题是否已被修正。';

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'AML 筛查规则的检测函数，逻辑与 KYC 版本一致：同样只返回每条记录的优先级最高发现，NULL 批次表示检查全部批次并取最新版本。';

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  '规则到案件类型的唯一映射表（单一事实来源）。报告要求"可报告的 KYC 缺口、身份不匹配、状态矛盾必须建立 KYC_GAP / IDENTITY_MISMATCH / STATUS_DISCREPANCY 案件"，这个函数就是这条要求的落地处。返回 NULL 表示该规则只登记质量问题、不建案件（例如级别为 LOW 的"身份尚未合并"提示）。';

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  '把一个校验发现登记成 Silver 层的数据质量问题（写入 silver.data_quality_issue）。问题编号由"批次 + 规则 + 记录"生成，因此重跑同一批次只会更新同一条问题而不会追加重复；问题状态先置为 OPEN，待问题条件消失后再由案件推进过程置为 RESOLVED。函数返回该规则对应的案件类型，供后续建案步骤使用。';

-- ============================================================================
-- 八、本模块创建的案件处理函数与过程
-- ============================================================================

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  '查找或建立验证案件：同一个 KYC 验证事件加同一种案件类型只保留一个案件，已存在则直接复用并返回其编号，不存在才新建。这样"同一个问题重复发现"不会产生一堆重复案件。';

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  '查找或建立 AML 调查案件，复用逻辑与验证案件一致。立案时间取触发筛查的业务时间，而不是当前时间，避免重跑导致账龄虚增。';

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  '按发现所属的表分派到对应的建案函数：KYC 类发现交给验证案件函数并返回案件编号，AML 类发现交给 AML 案件函数并返回 NULL。返回 NULL 是因为数据质量问题表只有验证案件这一列外键，AML 案件不需要也无法回填到那一列。';

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  '为所有仍处于 OPEN 的发现建立或复用案件：KYC 类发现会把案件编号回填到数据质量问题表，形成"检测 → 案件 → 报表"的可追溯链路。可重复执行，已建过案件的发现不会重复建案。';

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  '案件状态推进过程，做三件事：(1) 把当前规则已不再报告的 OPEN 问题置为 RESOLVED；(2) 把"最后一个未结问题也已清除"的验证案件置为 RESOLVED 并写明解决结论；(3) 把警报已不再成立的 AML 案件置为 CLOSED 并写明结案结论。仍然存在问题的事项保持未结，从而让异常账龄能够持续累积。';

-- ============================================================================
-- 九、Gold 层异常事实刷新过程
-- ============================================================================

COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  '刷新合规异常累积事实表：把两类案件（验证案件与 AML 案件）合并写入事实表，每行只填一个来源案件编号，按报告基准日重算账龄，未结案件更新原行而不是新增。同时补上金客户代理键（若维度表已有该客户），并清理来源案件已不复存在的陈旧事实行。可重复执行。';
