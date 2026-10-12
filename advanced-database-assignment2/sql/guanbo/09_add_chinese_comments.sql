-- PostgreSQL 15+
-- Member 5ï¼šç»™æœ¬æ¨¡å—æ‹¥æœ‰çš„å…¨éƒ¨æ•°æ®åº“å¯¹è±¡è¡¥ä¸­æ–‡æ³¨é‡Šã€‚
--
-- è¯´æ˜Žï¼š
--   1. PostgreSQL ç”¨ COMMENT ON ... IS '...' åŠ æ³¨é‡Šï¼Œä¸æ˜¯ MySQL çš„ COMMENT å…³é”®å­—ã€‚
--   2. æ³¨é‡Šæ˜¯"è¦†ç›–"è€Œä¸æ˜¯"è¿½åŠ "ï¼Œæ¯ä¸ªå¯¹è±¡åªèƒ½æœ‰ä¸€æ¡ã€‚æ‰§è¡Œæœ¬è„šæœ¬åŽï¼Œè¿™äº›å¯¹è±¡åœ¨
--      æ•°æ®åº“é‡Œæ˜¾ç¤ºçš„å°±æ˜¯ä¸­æ–‡ï¼ˆè„šæœ¬é‡ŒåŽŸæ¥çš„è‹±æ–‡æ³¨é‡Šè¢«æ›¿æ¢æŽ‰ï¼‰ã€‚
--   3. åªè¦†ç›–æœ¬æ¨¡å—è‡ªå·±æ‹¥æœ‰çš„å¯¹è±¡ï¼Œä¸ç¢°å…¶ä»–æˆå‘˜çš„è¡¨ï¼Œé¿å…è¦†ç›–åˆ«äººçš„æ³¨é‡Šã€‚
--   4. å¯é‡å¤æ‰§è¡Œï¼ŒCOMMENT ON å¤©ç„¶å¹‚ç­‰ã€‚
--
-- æ‰§è¡Œæ—¶æœºï¼š00-07 å»ºå®Œå¯¹è±¡ä¹‹åŽå†æ‰§è¡Œï¼Œä»»ä½•æ—¶é—´é‡å¤æ‰§è¡Œéƒ½å¯ä»¥ã€‚

-- ============================================================================
-- ä¸€ã€Silverï¼šKYC éªŒè¯äº‹ä»¶è¡¨
-- ============================================================================
COMMENT ON TABLE silver.kyc_verification_record IS
  'KYC éªŒè¯äº‹ä»¶è¡¨ã€‚ä¸€è¡Œä»£è¡¨"æŸå®¢æˆ·åœ¨æŸå¤©åšäº†ä¸€æ¬¡ä»€ä¹ˆç±»åž‹çš„éªŒè¯ã€ç»“æžœå¦‚ä½•"ï¼Œæ˜¯äº‹ä»¶æµæ°´è€Œä¸æ˜¯å®¢æˆ·å±žæ€§ï¼Œæ‰€ä»¥åŒä¸€å®¢æˆ·ä¼šæœ‰å¤šè¡Œã€‚ä¸šåŠ¡é”®æ˜¯"æ¥æºç³»ç»Ÿ + æ¥æº KYC ç¼–å·"ï¼Œé‡å¤å¯¼å…¥ä¸ä¼šäº§ç”Ÿé‡å¤è¡Œã€‚æ¯æ¡è®°å½•å¿…é¡»è‡³å°‘èƒ½æŒ‡å‘ä¸€ä¸ªèº«ä»½ï¼ˆé‡‘å®¢æˆ·æˆ–æ¥æºå®¢æˆ·è®°å½•ï¼‰ï¼Œä¸¤è€…éƒ½å¡«æ—¶å¿…é¡»æŒ‡å‘åŒä¸€ä¸ªäººã€‚æœ¬è¡¨æ˜¯ Member 5 æ‰€æœ‰åˆè§„åˆ¤å®šçš„æ•°æ®åŸºç¡€ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.kyc_verification_id IS
  'ä¸»é”®ã€‚ç”±"æ¥æºç³»ç»Ÿ + æ¥æº KYC ç¼–å·"ç”¨ MD5 ç¨³å®šç”Ÿæˆï¼Œé‡å¤å¤„ç†åŒä¸€æ‰¹æ•°æ®å¾—åˆ°åŒä¸€ä¸ªç¼–å·ï¼Œä¸ä¼šé‡å¤æ’å…¥ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.customer_id IS
  'å·²åˆå¹¶æˆåŠŸçš„é‡‘å®¢æˆ·ç¼–å·ï¼Œå…³è” silver.customer_masterã€‚ä¸ºç©ºè¡¨ç¤ºèº«ä»½å°šæœªåˆå¹¶å®Œæˆã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.source_customer_record_id IS
  'æ¥æºå®¢æˆ·è®°å½•ç¼–å·ï¼Œå…³è” silver.source_customer_recordï¼Œè¡¨ç¤º"è¿™æ¬¡éªŒè¯æ˜¯é’ˆå¯¹æ¥æºç³»ç»Ÿé‡Œå“ªæ¡å®¢æˆ·è®°å½•åšçš„"ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.source_system_id IS
  'æ¥æºç³»ç»Ÿç¼–å·ã€‚æœ¬æ¨¡å—æ•°æ®å‡æ¥è‡ª AML/KYC ç³»ç»Ÿï¼ˆAMLKYCï¼‰ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.reviewed_by IS
  'å®¡æ ¸äººï¼Œå…³è” silver.user_accountã€‚å¯é€‰ï¼›éªŒè¯é€šè¿‡æ—¶æ‰å¯èƒ½æœ‰å€¼ï¼Œç¼ºè¯ä»¶çš„è®°å½•ä¸åº”å¡«å®¡æ ¸äººã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.source_kyc_reference IS
  'æ¥æºç³»ç»Ÿçš„ KYC äº‹ä»¶ç¼–å·ï¼ˆå¦‚ VFY-004ï¼‰ï¼ŒåŠ æ¥æºç³»ç»ŸåŽå”¯ä¸€ï¼Œç”¨äºŽä¸Žæºæ•°æ®å¯¹è´¦ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.verification_type IS
  'éªŒè¯ç±»åž‹ï¼šIDENTITY_DOCUMENT èº«ä»½è¯ä»¶ã€ADDRESS_VERIFICATION åœ°å€éªŒè¯ã€SOURCE_OF_FUNDS èµ„é‡‘æ¥æºã€ENHANCED_DUE_DILIGENCE å¼ºåŒ–å°½è°ƒã€PERIODIC_REVIEW å®šæœŸå¤æ ¸ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.verification_status IS
  'éªŒè¯ç»“æžœï¼šVERIFIED å·²é€šè¿‡ã€PENDING å¾…å¤„ç†ã€MISSING_DOCUMENT ç¼ºè¯ä»¶ã€FAILED å¤±è´¥ã€EXPIRED å·²è¿‡æœŸã€‚ç¼ºè¯ä»¶/å¾…å¤„ç†/å¤±è´¥å±žäºŽ"èµ„æ–™ä¸å®Œæ•´"ï¼Œä¼šäº§ç”Ÿ KYC_GAP å¼‚å¸¸ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.verification_date IS
  'æœ¬æ¬¡éªŒè¯å‘ç”Ÿçš„ä¸šåŠ¡æ—¶é—´ã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.expiry_date IS
  'éªŒè¯ç»“æžœçš„æœ‰æ•ˆæœŸæˆªæ­¢æ—¥ã€‚åˆ¤æ–­"è¿™æ¬¡éªŒè¯è¿˜èƒ½ä¸èƒ½å¤ç”¨"å°±æ˜¯æ‹¿å®ƒè·ŸæŠ¥å‘ŠåŸºå‡†æ—¥æ¯”è¾ƒï¼šæ™šäºŽåŸºå‡†æ—¥æ‰ç®—ä»æœ‰æ•ˆã€‚ä¸ºç©ºè¡¨ç¤ºä¸é™æœ‰æ•ˆæœŸã€‚';
COMMENT ON COLUMN silver.kyc_verification_record.risk_level_at_verification IS
  'åšè¿™æ¬¡éªŒè¯æ—¶çš„é£Žé™©ç­‰çº§ï¼ˆLOW/MEDIUM/HIGH ç­‰ï¼‰ã€‚å±žå½“æ—¶å¿«ç…§ï¼Œä¸éšåŽç»­é£Žé™©å˜åŒ–è€Œæ”¹å˜ã€‚';

-- ============================================================================
-- äºŒã€Silverï¼šéªŒè¯æ¡ˆä»¶è¡¨
-- ============================================================================
COMMENT ON TABLE silver.special_verification_case IS
  'éªŒè¯æ¡ˆä»¶è¡¨ã€‚ä¸€è¡Œä»£è¡¨"ä¸€ä¸ªéœ€è¦äººå·¥è·Ÿè¿›çš„ KYC é—®é¢˜"ï¼Œæ˜¯æ¡ˆä»¶è€Œéžäº‹ä»¶ï¼šåŒä¸€éªŒè¯äº‹ä»¶åªå¯¹åº”ä¸€ä¸ªæ¡ˆä»¶ã€‚æ¡ˆä»¶ç±»åž‹é™å®šä¸º KYC_GAPï¼ˆèµ„æ–™ç¼ºå¤±ï¼‰ã€IDENTITY_MISMATCHï¼ˆèº«ä»½å¯¹ä¸ä¸Šï¼‰ã€STATUS_DISCREPANCYï¼ˆçŠ¶æ€çŸ›ç›¾ï¼‰ä¸‰ç§ï¼Œæ­£æ˜¯æŠ¥å‘Šè¦æ±‚çš„æŠ¥å‘Šå£å¾„ã€‚å¿…é¡»è‡³å°‘æœ‰ä¸€ä¸ªä¸»ä½“æˆ–è§¦å‘å¼•ç”¨ï¼ˆå®¢æˆ·ã€æ¥æºè®°å½•ã€åŒ¹é…è®°å½•ã€éªŒè¯äº‹ä»¶å››è€…ä¹‹ä¸€ï¼‰ï¼Œå…è®¸èº«ä»½æœªç¡®è®¤æ—¶å…ˆå»ºæ¡ˆã€‚';
COMMENT ON COLUMN silver.special_verification_case.verification_case_id IS
  'ä¸»é”®ã€‚ç”±"è§¦å‘çš„éªŒè¯äº‹ä»¶ + æ¡ˆä»¶ç±»åž‹"ç¨³å®šç”Ÿæˆï¼ŒåŒä¸€é—®é¢˜é‡å¤æ£€æµ‹ä¼šå¤ç”¨åŒä¸€æ¡ˆä»¶ï¼Œä¸ä¼šé‡å¤å»ºæ¡ˆã€‚';
COMMENT ON COLUMN silver.special_verification_case.customer_id IS
  'æ¡ˆä»¶æ¶‰åŠçš„é‡‘å®¢æˆ·ç¼–å·ï¼Œå…³è” silver.customer_masterã€‚å¯ä¸ºç©ºï¼Œè¡¨ç¤ºèº«ä»½å°šæœªç¡®è®¤ã€‚';
COMMENT ON COLUMN silver.special_verification_case.source_customer_record_id IS
  'æ¡ˆä»¶æ¶‰åŠçš„æ¥æºå®¢æˆ·è®°å½•ç¼–å·ï¼Œå…³è” silver.source_customer_recordã€‚èº«ä»½æœªåˆå¹¶æ—¶é å®ƒé”å®šå½“äº‹äººã€‚';
COMMENT ON COLUMN silver.special_verification_case.match_id IS
  'å…³è”çš„å®¢æˆ·åŒ¹é…è®°å½•ç¼–å·ï¼Œå…³è” silver.customer_source_matchï¼Œç”¨äºŽ"åŒ¹é…å­˜ç–‘"ç±»æ¡ˆä»¶ã€‚';
COMMENT ON COLUMN silver.special_verification_case.kyc_verification_id IS
  'è§¦å‘æœ¬æ¡ˆä»¶çš„ KYC éªŒè¯äº‹ä»¶ç¼–å·ï¼Œå…³è” silver.kyc_verification_recordã€‚';
COMMENT ON COLUMN silver.special_verification_case.assigned_user_id IS
  'æ¡ˆä»¶å¤„ç†äººï¼Œå…³è” silver.user_accountã€‚å¯ä¸ºç©ºï¼ˆå°šæœªæŒ‡æ´¾ï¼‰ã€‚';
COMMENT ON COLUMN silver.special_verification_case.case_type IS
  'æ¡ˆä»¶ç±»åž‹ï¼Œä»…ä¸‰ç§ï¼šKYC_GAP èµ„æ–™ç¼ºå¤±ã€IDENTITY_MISMATCH èº«ä»½ä¸åŒ¹é…ã€STATUS_DISCREPANCY çŠ¶æ€çŸ›ç›¾ã€‚ä¸ŽæŠ¥å‘Šè¦æ±‚ä¸€ä¸€å¯¹åº”ã€‚';
COMMENT ON COLUMN silver.special_verification_case.trigger_type IS
  'è§¦å‘æ¥æºç±»åˆ«ï¼šGOLDEN_CUSTOMER ç”±å·²åˆå¹¶å®¢æˆ·è§¦å‘ã€SOURCE_CUSTOMER_RECORD ç”±æ¥æºå®¢æˆ·è®°å½•è§¦å‘ã€‚è¯´æ˜Žè¿™æ¡æ¡ˆä»¶å‡­ä»€ä¹ˆå»ºç«‹ã€‚';
COMMENT ON COLUMN silver.special_verification_case.case_reason IS
  'ç«‹æ¡ˆåŽŸå› ï¼Œæ ¼å¼"è§„åˆ™å: é—®é¢˜æè¿°"ï¼Œæœ€é•¿ 1000 å­—ç¬¦ã€‚çœ‹ä¸€çœ¼å°±çŸ¥é“ä¸ºä»€ä¹ˆå¼€æ¡ˆã€‚';
COMMENT ON COLUMN silver.special_verification_case.case_status IS
  'æ¡ˆä»¶çŠ¶æ€ï¼šOPEN å¾…å¤„ç†ã€IN_REVIEW å¤„ç†ä¸­ã€RESOLVED å·²è§£å†³ã€CLOSED å·²å…³é—­ã€‚çŠ¶æ€ä¸Ž resolved_at å¿…é¡»ä¸€è‡´ã€‚';
COMMENT ON COLUMN silver.special_verification_case.severity IS
  'ä¸¥é‡ç¨‹åº¦ï¼šLOW ä½Žã€MEDIUM ä¸­ã€HIGH é«˜ã€CRITICAL ç´§æ€¥ã€‚ç”±æ£€æµ‹è§„åˆ™çš„çº§åˆ«æ˜ å°„è€Œæ¥ã€‚';
COMMENT ON COLUMN silver.special_verification_case.opened_at IS
  'ç«‹æ¡ˆæ—¶é—´ã€‚å–è§¦å‘äº‹ä»¶çš„ä¸šåŠ¡æ—¶é—´è€Œéžè„šæœ¬è¿è¡Œæ—¶é—´ï¼Œè¿™æ ·é‡è·‘è„šæœ¬ä¸ä¼šè®©è´¦é¾„å‡­ç©ºå˜å¤§ã€‚';
COMMENT ON COLUMN silver.special_verification_case.resolved_at IS
  'è§£å†³æ—¶é—´ã€‚ä»…å½“çŠ¶æ€ä¸º RESOLVED æˆ– CLOSED æ—¶æ‰æœ‰å€¼ã€‚';
COMMENT ON COLUMN silver.special_verification_case.resolution_outcome IS
  'è§£å†³ç»“è®ºã€‚è¯´æ˜Žè¿™æ¡æ¡ˆä»¶å› ä¸ºä»€ä¹ˆè¢«åˆ¤å®šä¸ºå·²æ¸…é™¤ã€‚';

-- ============================================================================
-- ä¸‰ã€Silverï¼šAML ç­›æŸ¥äº‹ä»¶è¡¨
-- ============================================================================
COMMENT ON TABLE silver.aml_screening_result IS
  'AML åæ´—é’±ç­›æŸ¥äº‹ä»¶è¡¨ã€‚ä¸€è¡Œä»£è¡¨"æŸå®¢æˆ·åœ¨æŸå¤©è¢«åå•åº“ç­›æŸ¥äº†ä¸€æ¬¡ã€å‘½ä¸­ç¨‹åº¦å¦‚ä½•"ï¼Œæ˜¯äº‹ä»¶æµæ°´ï¼ŒåŒä¸€å®¢æˆ·å¯æœ‰å¤šæ¡ã€‚ä¸šåŠ¡é”®æ˜¯"æ¥æºç³»ç»Ÿ + æ¥æºç­›æŸ¥ç¼–å·"ã€‚å…³é”®å«ä¹‰ï¼šç­›æŸ¥å‘½ä¸­ï¼ˆPOTENTIAL_MATCH ç­‰ï¼‰åªæ˜¯"ç–‘ä¼¼"ï¼Œä¸ç­‰äºŽç¡®è®¤æœ‰é—®é¢˜ï¼Œæ‰€ä»¥å®ƒåªè§¦å‘æ¡ˆä»¶å¤æ ¸ï¼Œä¸ç›´æŽ¥å®šæ€§ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.aml_screening_id IS
  'ä¸»é”®ã€‚ç”±"æ¥æºç³»ç»Ÿ + æ¥æºç­›æŸ¥ç¼–å·"ç”¨ MD5 ç¨³å®šç”Ÿæˆï¼Œé‡å¤å¤„ç†ä¸ä¼šé‡å¤æ’å…¥ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.customer_id IS
  'è¢«ç­›æŸ¥çš„é‡‘å®¢æˆ·ç¼–å·ï¼Œå…³è” silver.customer_masterã€‚å¯ä¸ºç©ºï¼ˆèº«ä»½æœªåˆå¹¶ï¼‰ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.source_customer_record_id IS
  'è¢«ç­›æŸ¥çš„æ¥æºå®¢æˆ·è®°å½•ç¼–å·ï¼Œå…³è” silver.source_customer_recordã€‚';
COMMENT ON COLUMN silver.aml_screening_result.source_system_id IS
  'æ¥æºç³»ç»Ÿç¼–å·ã€‚æœ¬æ¨¡å—æ•°æ®æ¥è‡ª AML/KYC ç³»ç»Ÿï¼ˆAMLKYCï¼‰ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.source_screening_reference IS
  'æ¥æºç³»ç»Ÿçš„ç­›æŸ¥äº‹ä»¶ç¼–å·ï¼ˆå¦‚ SCR-005-2ï¼‰ï¼ŒåŠ æ¥æºç³»ç»ŸåŽå”¯ä¸€ï¼Œç”¨äºŽä¸Žæºæ•°æ®å¯¹è´¦ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.screening_type IS
  'åå•ç±»åˆ«ï¼šSANCTIONS åˆ¶è£åå•ã€PEP æ”¿æ²»å…¬ä¼—äººç‰©ã€WATCHLIST ç›‘æŽ§åå•ã€ADVERSE_MEDIA è´Ÿé¢æ–°é—»ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.screening_date IS
  'æœ¬æ¬¡ç­›æŸ¥å‘ç”Ÿçš„ä¸šåŠ¡æ—¶é—´ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.screening_result IS
  'ç­›æŸ¥ç»“è®ºï¼šCLEAR æœªå‘½ä¸­ã€POTENTIAL_MATCH ç–‘ä¼¼å‘½ä¸­ã€CONFIRMED_MATCH ç¡®è®¤å‘½ä¸­ã€FALSE_POSITIVE è¯¯æŠ¥ã€‚å‰ä¸¤è€…å±ž"è­¦æŠ¥"ï¼Œå¿…é¡»è¿›å…¥å¤æ ¸ã€‚';
COMMENT ON COLUMN silver.aml_screening_result.match_score IS
  'ä¸Žåå•çš„ç›¸ä¼¼åº¦å¾—åˆ†ï¼Œå–å€¼ 0.0000 åˆ° 1.0000ã€‚è¶Šé«˜è¶ŠæŽ¥è¿‘åå•äººå‘˜ï¼›å®ƒæ˜¯åˆ¤å®šä¾æ®è€Œä¸æ˜¯æœ€ç»ˆç»“è®ºã€‚';
COMMENT ON COLUMN silver.aml_screening_result.provider_reference IS
  'å¤–éƒ¨ç­›æŸ¥æœåŠ¡å•†è¿”å›žçš„æµæ°´å·ï¼Œç”¨äºŽå‘ä¾›åº”å•†è¿½æŸ¥åŽŸå§‹ç»“æžœã€‚';
COMMENT ON COLUMN silver.aml_screening_result.review_required_flag IS
  'æ˜¯å¦éœ€è¦äººå·¥å¤æ ¸ã€‚è­¦æŠ¥ç±»ç»“è®ºå¿…é¡»ä¸ºçœŸï¼›è‹¥ä¸ºå‡è¯´æ˜Žæºç³»ç»Ÿæ¼æ ‡äº†å¤æ ¸è¦æ±‚ï¼Œä¼šäº§ç”Ÿ STATUS_DISCREPANCY å¼‚å¸¸ã€‚';

-- ============================================================================
-- å››ã€Silverï¼šAML è°ƒæŸ¥æ¡ˆä»¶è¡¨
-- ============================================================================
COMMENT ON TABLE silver.aml_case IS
  'AML è°ƒæŸ¥æ¡ˆä»¶è¡¨ã€‚ä¸€è¡Œä»£è¡¨"ä¸€æ¬¡é’ˆå¯¹æ´—é’±/åˆ¶è£é£Žé™©çš„è°ƒæŸ¥"ï¼Œå¯ç”±ç­›æŸ¥å‘½ä¸­è§¦å‘ï¼Œä¹Ÿå¯ç”±å…¶ä»–æœ‰æ®å¯æŸ¥çš„ä¿¡å·è§¦å‘ï¼ˆæ‰€ä»¥ç­›æŸ¥å¼•ç”¨å…è®¸ä¸ºç©ºï¼‰ã€‚ä¸ŽéªŒè¯æ¡ˆä»¶åˆ†è¡¨å­˜æ”¾ï¼Œæ˜¯ä¸ºäº†ä¸è®©"ç–‘ä¼¼å‘½ä¸­"è¢«å½“æˆ"å·²ç¡®è®¤é—®é¢˜"ã€‚å¿…é¡»è‡³å°‘æœ‰ä¸€ä¸ªä¸»ä½“æˆ–è§¦å‘ä¾æ®ï¼›çŠ¶æ€ä¸º CLOSED æ—¶å¿…é¡»æœ‰ç»“æ¡ˆæ—¶é—´ã€‚';
COMMENT ON COLUMN silver.aml_case.aml_case_id IS
  'ä¸»é”®ã€‚ç”±"è§¦å‘çš„ç­›æŸ¥äº‹ä»¶ + æ¡ˆä»¶ç±»åž‹"ç¨³å®šç”Ÿæˆï¼Œé‡å¤æ£€æµ‹ä¼šå¤ç”¨åŒä¸€æ¡ˆä»¶ã€‚';
COMMENT ON COLUMN silver.aml_case.customer_id IS
  'æ¡ˆä»¶æ¶‰åŠçš„é‡‘å®¢æˆ·ç¼–å·ï¼Œå…³è” silver.customer_masterã€‚å¯ä¸ºç©ºï¼ˆèº«ä»½æœªåˆå¹¶ï¼‰ã€‚';
COMMENT ON COLUMN silver.aml_case.source_customer_record_id IS
  'æ¡ˆä»¶æ¶‰åŠçš„æ¥æºå®¢æˆ·è®°å½•ç¼–å·ï¼Œå…³è” silver.source_customer_recordã€‚';
COMMENT ON COLUMN silver.aml_case.aml_screening_id IS
  'è§¦å‘æœ¬æ¡ˆä»¶çš„ç­›æŸ¥äº‹ä»¶ç¼–å·ï¼Œå…³è” silver.aml_screening_resultã€‚å…è®¸ä¸ºç©ºï¼Œè¡¨ç¤ºæ¡ˆä»¶æ¥è‡ªå…¶ä»–ä¿¡å·ã€‚';
COMMENT ON COLUMN silver.aml_case.assigned_user_id IS
  'è°ƒæŸ¥è´Ÿè´£äººï¼Œå…³è” silver.user_accountã€‚å¯ä¸ºç©ºã€‚';
COMMENT ON COLUMN silver.aml_case.trigger_type IS
  'è§¦å‘æ¥æºç±»åˆ«ï¼šSANCTIONS_SCREENING åˆ¶è£ç­›æŸ¥ã€PEP_SCREENING æ”¿è¦ç­›æŸ¥ã€WATCHLIST_SCREENING ç›‘æŽ§åå•ç­›æŸ¥ã€ADVERSE_MEDIA_SCREENING è´Ÿé¢æ–°é—»ç­›æŸ¥ã€SCREENING_ALERT å…¶ä»–ç­›æŸ¥è­¦æŠ¥ã€‚';
COMMENT ON COLUMN silver.aml_case.trigger_reference IS
  'è§¦å‘ä¾æ®çš„æ–‡å­—å¼•ç”¨ï¼Œæ ¼å¼"è§„åˆ™å: æ¥æºå®¢æˆ·ç¼–å·"ï¼Œä¾¿äºŽäººå·¥å›žæº¯è¿™æ¡æ¡ˆä»¶å‡­ä»€ä¹ˆå¼€ã€‚';
COMMENT ON COLUMN silver.aml_case.case_type IS
  'æ¡ˆä»¶ç±»åž‹ã€‚æœ¬æ¨¡å—å›ºå®šä½¿ç”¨ AML_SCREENING_REVIEWï¼ˆç­›æŸ¥è­¦æŠ¥å¤æ ¸ï¼‰ï¼Œå¼ºè°ƒè¿™æ˜¯å¤æ ¸è€Œä¸æ˜¯å®šæ€§ç»“è®ºã€‚';
COMMENT ON COLUMN silver.aml_case.case_status IS
  'æ¡ˆä»¶çŠ¶æ€ï¼šOPEN å¾…å¤„ç†ã€IN_REVIEW è°ƒæŸ¥ä¸­ã€CLOSED å·²ç»“æ¡ˆã€‚å·²ç»“æ¡ˆå¿…é¡»æœ‰ closed_atï¼Œæœªç»“æ¡ˆä¸èƒ½æœ‰ã€‚';
COMMENT ON COLUMN silver.aml_case.risk_level IS
  'æ¡ˆä»¶é£Žé™©ç­‰çº§ï¼šLOW/MEDIUM/HIGH/CRITICALã€‚ç”±æ£€æµ‹è§„åˆ™çº§åˆ«æ˜ å°„è€Œæ¥ã€‚';
COMMENT ON COLUMN silver.aml_case.opened_at IS
  'ç«‹æ¡ˆæ—¶é—´ã€‚å–è§¦å‘ç­›æŸ¥çš„ä¸šåŠ¡æ—¶é—´ï¼Œä¿è¯é‡è·‘è„šæœ¬ä¸æ”¹å˜è´¦é¾„ã€‚';
COMMENT ON COLUMN silver.aml_case.closed_at IS
  'ç»“æ¡ˆæ—¶é—´ã€‚ä»…å½“çŠ¶æ€ä¸º CLOSED æ—¶æ‰æœ‰å€¼ã€‚';
COMMENT ON COLUMN silver.aml_case.case_outcome IS
  'ç»“æ¡ˆç»“è®ºã€‚è¯´æ˜Žå¤æ ¸ç»“æžœä»¥åŠä¸ºä»€ä¹ˆä¸å†éœ€è¦è·Ÿè¿›ã€‚';

-- ============================================================================
-- äº”ã€Goldï¼šåˆè§„å¼‚å¸¸ç´¯ç§¯å¿«ç…§äº‹å®žè¡¨
-- ============================================================================
COMMENT ON TABLE gold.fact_compliance_exception IS
  'åˆè§„å¼‚å¸¸ç´¯ç§¯å¿«ç…§äº‹å®žè¡¨ï¼ˆKYC/AML å¼‚å¸¸æŠ¥è¡¨çš„æ•°æ®æºï¼‰ã€‚ä¸€è¡Œä»£è¡¨"ä¸€ä¸ªæ¥æºæ¡ˆä»¶"ï¼Œå±žç´¯ç§¯åž‹äº‹å®žï¼šæ¡ˆä»¶æœªç»“æ—¶æ¯æ¬¡åˆ·æ–°æ›´æ–°åŒä¸€è¡Œï¼Œè€Œä¸æ˜¯æ–°å¢žè¡Œï¼Œå› æ­¤èƒ½çœŸå®žåæ˜ "è¿™ç¬”å¼‚å¸¸æŒ‚äº†å¤šä¹…"ã€‚è§„åˆ™è¦æ±‚ verification_case_id ä¸Ž aml_case_id å¿…æœ‰ä¸”ä»…æœ‰ä¸€ä¸ªï¼Œå¹¶ä¸Ž exception_source_type ä¸€è‡´ï¼›æ¯ä¸ªæ¥æºæ¡ˆä»¶åœ¨å…¨è¡¨åªå‡ºçŽ°ä¸€æ¬¡ã€‚èº«ä»½æœªç¡®è®¤æ—¶ customer_key å…è®¸ä¸ºç©ºï¼ŒæŠ¥è¡¨ç”¨å·¦è¿žæŽ¥ä¿ç•™è¿™äº›è¡Œè€Œä¸æ˜¯ä¸¢æŽ‰ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_fact_id IS
  'ä¸»é”®ã€‚ç”±"æ¥æºç±»åž‹ + æ¥æºæ¡ˆä»¶ç¼–å·"ç¨³å®šç”Ÿæˆï¼Œåˆ·æ–°æ—¶èƒ½ç²¾ç¡®å‘½ä¸­åŒä¸€è¡Œåšæ›´æ–°ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.customer_key IS
  'å…³è” gold.dim_customer çš„ä»£ç†é”®ï¼ˆæ•°ä»“ç»´åº¦å¤–é”®ï¼Œä¸æ˜¯ä¸šåŠ¡ç¼–å·ï¼‰ã€‚èº«ä»½æœªç¡®è®¤æ—¶ä¸º NULLï¼Œç»´åº¦è¡¨æœ‰äº†è¯¥å®¢æˆ·çš„å½“å‰ç‰ˆæœ¬åŽä¼šè‡ªåŠ¨è¡¥ä¸Šã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.verification_case_id IS
  'æ¥æºä¸ºéªŒè¯æ¡ˆä»¶æ—¶çš„æ¡ˆä»¶ç¼–å·ï¼Œå…³è” silver.special_verification_caseã€‚æ¥æºç±»åž‹ä¸º AML æ—¶æœ¬åˆ—å¿…é¡»ä¸ºç©ºã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.aml_case_id IS
  'æ¥æºä¸º AML æ¡ˆä»¶æ—¶çš„æ¡ˆä»¶ç¼–å·ï¼Œå…³è” silver.aml_caseã€‚æ¥æºç±»åž‹ä¸º VERIFICATION æ—¶æœ¬åˆ—å¿…é¡»ä¸ºç©ºã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_source_type IS
  'å¼‚å¸¸æ¥æºç±»åž‹ï¼šVERIFICATION æ¥è‡ª KYC éªŒè¯æ¡ˆä»¶ã€AML æ¥è‡ªåæ´—é’±è°ƒæŸ¥æ¡ˆä»¶ã€‚æŠ¥è¡¨æŒ‰å®ƒåˆ†ç±»æ±‡æ€»ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_type IS
  'å¼‚å¸¸ç±»åž‹ï¼Œç»§æ‰¿æ¥æºæ¡ˆä»¶ç±»åž‹ï¼Œå¦‚ KYC_GAPã€STATUS_DISCREPANCYã€AML_SCREENING_REVIEWã€‚æŠ¥è¡¨çš„æ ¸å¿ƒåˆ†ç±»ç»´åº¦ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_status IS
  'å¼‚å¸¸çŠ¶æ€ï¼šOPEN æœªç»“ã€IN_REVIEW å¤„ç†ä¸­ã€RESOLVED å·²è§£å†³ã€CLOSED å·²å…³é—­ã€‚ç”±æ¡ˆä»¶çŠ¶æ€æ˜ å°„è€Œæ¥ï¼Œæ˜¯äº‹å®žè¡¨è‡ªå·±å¯¹æ¡ˆä»¶çš„çœ‹æ³•ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.severity IS
  'ä¸¥é‡ç¨‹åº¦ï¼šLOW/MEDIUM/HIGH/CRITICALã€‚ç»§æ‰¿è‡ªæ¥æºæ¡ˆä»¶ï¼ŒæŠ¥è¡¨æŽ’åºä¸Žæ±‡æ€»å–æœ€é«˜çº§åˆ«æ—¶ä½¿ç”¨ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.opened_date IS
  'å¼€æ¡ˆæ—¥æœŸï¼ˆå–æ¡ˆä»¶ç«‹æ¡ˆæ—¶é—´çš„æ—¥æœŸéƒ¨åˆ†ï¼‰ï¼Œè´¦é¾„è®¡ç®—çš„èµ·ç‚¹ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.resolved_date IS
  'ç»“æ¡ˆæ—¥æœŸã€‚æœªç»“æ¡ˆæ—¶ä¸º NULLã€‚æ³¨æ„ï¼šç®—è´¦é¾„æ—¶ä¼šæŠŠç»“æ¡ˆæ—¥æŒ‰æŠ¥å‘ŠåŸºå‡†æ—¥å°é¡¶ï¼Œé¿å…å‡ºçŽ°"æ¯”æŠ¥å‘ŠæœŸè¿˜ä¹…"çš„å¼‚å¸¸ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.as_of_date IS
  'æœ¬è¡Œæ•°æ®çš„æŠ¥å‘ŠåŸºå‡†æ—¥ï¼ˆæ•°æ®æˆªæ­¢åˆ°å“ªå¤©ï¼‰ã€‚æŠ¥è¡¨æŒ‰å®ƒç­›é€‰ï¼Œæœªç»“æ¡ˆä»¶çš„è´¦é¾„ä¹Ÿç®—åˆ°è¿™ä¸€å¤©ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.days_open IS
  'å¼‚å¸¸å·²æŒ‚å¤©æ•° = ç»“æ¡ˆæ—¥ï¼ˆæœªç»“æ¡ˆæ—¶å–æŠ¥å‘ŠåŸºå‡†æ—¥ï¼‰å‡åŽ»å¼€æ¡ˆæ—¥ï¼Œä¸”ä¸ä¼šè¶…è¿‡æŠ¥å‘ŠåŸºå‡†æ—¥ã€‚æŠ¥è¡¨çš„è´¦é¾„åˆ—ã€‚';
COMMENT ON COLUMN gold.fact_compliance_exception.last_updated_at IS
  'æœ¬è¡Œæœ€åŽä¸€æ¬¡åˆ·æ–°çš„æ—¶é—´ã€‚ç”¨äºŽç¡®è®¤æ•°æ®æ–°é²œåº¦ï¼Œä»¥åŠåˆ¤æ–­æœªç»“æ¡ˆä»¶æ˜¯å¦è¢«æ›´æ–°è¿‡ã€‚';

-- ============================================================================
-- å…­ã€è§†å›¾
-- ============================================================================
COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'KYC/AML å¼‚å¸¸æŠ¥è¡¨ä¸»è§†å›¾ï¼šä¸€è¡Œä¸€ç¬”åˆè§„å¼‚å¸¸ï¼Œå¹¶å¸¦å‡ºæ¥æºæ¡ˆä»¶çš„è§¦å‘ç±»åž‹ã€ç«‹æ¡ˆåŽŸå› ã€å…³è”éªŒè¯æˆ–ç­›æŸ¥äº‹ä»¶ã€ç»“æ¡ˆç»“è®ºã€‚èº«ä»½æœªç¡®è®¤çš„å¼‚å¸¸é€šè¿‡å·¦è¿žæŽ¥ä¿ç•™ï¼Œä¸ä¼šè¢«è¿‡æ»¤æŽ‰ï¼Œç¬¦åˆ"æœªè§£å†³èº«ä»½ä¹Ÿè¦å‡ºçŽ°åœ¨ç›‘ç®¡æŠ¥è¡¨é‡Œ"çš„è¦æ±‚ã€‚';
COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  'åˆè§„å¼‚å¸¸æ±‡æ€»è§†å›¾ï¼šæŒ‰å®¢æˆ· + æ¥æº + å¼‚å¸¸ç±»åž‹èšåˆï¼Œç»™å‡ºå¼‚å¸¸æ€»æ•°ã€æœªç»“æ•°ã€å·²ç»“æ•°ã€æœ€é•¿æŒ‚è´¦å¤©æ•°ä¸Žæœ€é«˜ä¸¥é‡ç¨‹åº¦ã€‚ä¾›æŠ¥è¡¨æ±‡æ€»åŒºå—ç›´æŽ¥ä½¿ç”¨ã€‚æœ€é«˜ä¸¥é‡ç¨‹åº¦æŒ‰ CRITICAL > HIGH > MEDIUM > LOW çš„æ˜¾å¼æŽ’åºå–å¾—ï¼Œä¸æ˜¯æŒ‰å­—æ¯æŽ’åºã€‚';
COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  'åˆè§„å¼‚å¸¸æ•°æ®è¡€ç¼˜è§†å›¾ï¼šæŠŠ"Bronze åŽŸå§‹è®°å½• â†’ Silver å‘å¸ƒäº‹ä»¶ â†’ åˆè§„æ¡ˆä»¶ â†’ Gold å¼‚å¸¸äº‹å®ž"ä¸²æˆä¸€æ¡å¯è¿½æº¯é“¾è·¯ï¼Œç”¨äºŽå‘å®¡è®¡è¯´æ˜Žæ¯ä¸ªå¼‚å¸¸ç»“è®ºæ˜¯æ€Žä¹ˆæ¥çš„ã€‚';

-- ============================================================================
-- ä¸ƒã€æ ‡è¯†ç”Ÿæˆå‡½æ•°
-- ============================================================================
COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  'ç”±"æ¥æºç³»ç»Ÿ + æ¥æº KYC ç¼–å·"ç”Ÿæˆç¨³å®šçš„éªŒè¯äº‹ä»¶ä¸»é”®ï¼Œä½¿é‡å¤å¤„ç†å¾—åˆ°åŒä¸€ç¼–å·ï¼Œä¸”åˆ«å¤„æ— éœ€å›žæŸ¥æ•°æ®åº“å³å¯å®šä½å·²å‘å¸ƒäº‹ä»¶ã€‚';
COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  'ç”±"æ¥æºç³»ç»Ÿ + æ¥æºç­›æŸ¥ç¼–å·"ç”Ÿæˆç¨³å®šçš„ç­›æŸ¥äº‹ä»¶ä¸»é”®ï¼Œä½œç”¨åŒ KYC ç‰ˆæœ¬ã€‚';
COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  'ç”±"æ¥æºç±»åž‹ + æ¥æºæ¡ˆä»¶ç¼–å·"ç”Ÿæˆå¼‚å¸¸äº‹å®žè¡¨ä¸»é”®ï¼Œä¿è¯åŒä¸€æ¡ˆä»¶æ°¸è¿œå¯¹åº”åŒä¸€è¡Œäº‹å®žï¼Œä»Žè€Œå®žçŽ°"åˆ·æ–°è€Œéžæ–°å¢ž"ã€‚';

-- ============================================================================
-- å…«ã€è£…è½½è¿‡ç¨‹
-- ============================================================================
COMMENT ON PROCEDURE silver.stage_bronze_batch(varchar, varchar) IS
  'æŠŠæŒ‡å®šæ‰¹æ¬¡çš„ Bronze åŽŸå§‹è¡Œç™»è®°åˆ°ä¸´æ—¶è¡¨ï¼Œå¹¶è¡¥ä¸Šèº«ä»½æŸ¥æ‰¾ç»“æžœï¼ˆæ¥æºå®¢æˆ·è®°å½•ç¼–å·ä¸Žé‡‘å®¢æˆ·ç¼–å·ï¼‰ã€‚KYC ä¸Ž AML å…±ç”¨è¿™ä¸€æ­¥ã€‚';
COMMENT ON PROCEDURE silver.record_event_lineage(varchar, varchar) IS
  'æŠŠå·²å‘å¸ƒåˆ° Silver çš„äº‹ä»¶è®°å…¥æ•°æ®è¡€ç¼˜è¡¨ï¼Œå½¢æˆ"Bronze åŽŸå§‹è¡Œ â†’ Silver äº‹ä»¶"çš„é“¾è·¯ã€‚é‡å¤å‘å¸ƒä¸ä¼šäº§ç”Ÿé‡å¤è¡€ç¼˜ã€‚';
COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  'ä¸º KYC/AML äº‹ä»¶å»ºç«‹æœ€å°çš„å®¢æˆ·èº«ä»½ï¼šå…ˆå»ºæ¥æºå®¢æˆ·è®°å½•ï¼Œå†å»ºé‡‘å®¢æˆ·è®°å½•ä¸ŽåŒ¹é…å…³ç³»ã€‚ç»ä¸ä¿®æ”¹å…¶ä»–æˆå‘˜å·²è§£æžå¥½çš„èº«ä»½ï¼Œåªè¡¥é½æœ¬æ¨¡å—äº‹ä»¶å¼•ç”¨è€Œå°šä¸å­˜åœ¨çš„é‚£äº›ã€‚';
COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'æŠŠä¸€æ‰¹ Bronze KYC éªŒè¯è¡Œæ ¡éªŒåŽå‘å¸ƒåˆ° Silverï¼›å­˜åœ¨é˜»æ–­çº§é—®é¢˜çš„è¡Œä¸äºˆå‘å¸ƒï¼Œå¹¶åœ¨æ•°æ®è´¨é‡é—®é¢˜è¡¨ç•™ç—•ã€‚å¯é‡å¤æ‰§è¡Œã€‚';
COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'æŠŠä¸€æ‰¹ Bronze AML ç­›æŸ¥è¡Œæ ¡éªŒåŽå‘å¸ƒåˆ° Silverï¼Œé€»è¾‘ä¸Ž KYC ç‰ˆæœ¬ä¸€è‡´ã€‚';
COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Member 5 æ‰¹æ¬¡æ€»å…¥å£ï¼šå»ºç«‹å®¢æˆ·èº«ä»½ â†’ å‘å¸ƒ KYC ä¸Ž AML äº‹ä»¶åˆ° Silver â†’ è·‘å…¨éƒ¨æ ¡éªŒè§„åˆ™å¹¶ç™»è®°æ•°æ®è´¨é‡é—®é¢˜ã€‚å‚è€ƒæ—¥æœŸç”¨äºŽåˆ¤æ–­éªŒè¯æ˜¯å¦è¿‡æœŸã€‚';
COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'ä¸ºæ‰€æœ‰ä»å¤„äºŽ OPEN çš„å‘çŽ°å»ºç«‹æˆ–å¤ç”¨æ¡ˆä»¶ï¼Œå¹¶æŠŠ KYC ç±»å‘çŽ°çš„æ¡ˆä»¶å·å›žå¡«åˆ°æ•°æ®è´¨é‡é—®é¢˜è¡¨ï¼Œå½¢æˆ"æ£€æµ‹ â†’ æ¡ˆä»¶ â†’ æŠ¥è¡¨"çš„å¯è¿½æº¯é“¾è·¯ã€‚å¯é‡å¤æ‰§è¡Œã€‚';
COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'æ¡ˆä»¶çŠ¶æ€æŽ¨è¿›ï¼šï¼ˆ1ï¼‰è§„åˆ™å·²ä¸å†æŠ¥å‘Šçš„ OPEN é—®é¢˜ç½®ä¸º RESOLVEDï¼›ï¼ˆ2ï¼‰æœ€åŽä¸€ä¸ªæœªç»“é—®é¢˜ä¹Ÿæ¸…é™¤çš„éªŒè¯æ¡ˆä»¶ç½®ä¸º RESOLVED å¹¶å†™æ˜Žç»“è®ºï¼›ï¼ˆ3ï¼‰è­¦æŠ¥ä¸å†æˆç«‹çš„ AML æ¡ˆä»¶ç½®ä¸º CLOSED å¹¶å†™æ˜Žç»“è®ºã€‚ä»å­˜åœ¨çš„é—®é¢˜ä¿æŒæœªç»“ï¼Œä½¿å¼‚å¸¸è´¦é¾„èƒ½æŒç»­ç´¯ç§¯ã€‚';
COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  'åˆ·æ–°åˆè§„å¼‚å¸¸ç´¯ç§¯äº‹å®žè¡¨ï¼šåˆå¹¶ä¸¤ç±»æ¡ˆä»¶å†™å…¥äº‹å®žè¡¨ï¼Œæ¯è¡Œåªå¡«ä¸€ä¸ªæ¥æºæ¡ˆä»¶ç¼–å·ï¼ŒæŒ‰æŠ¥å‘ŠåŸºå‡†æ—¥é‡ç®—è´¦é¾„ï¼Œæœªç»“æ¡ˆä»¶æ›´æ–°åŽŸè¡Œè€Œéžæ–°å¢žï¼›è¡¥ä¸Šé‡‘å®¢æˆ·ä»£ç†é”®ï¼›æ¸…ç†æ¥æºæ¡ˆä»¶å·²ä¸å­˜åœ¨çš„é™ˆæ—§è¡Œã€‚å¯é‡å¤æ‰§è¡Œã€‚';

-- ============================================================================
-- ä¹ã€æ ¡éªŒä¸Žæ¡ˆä»¶å‡½æ•°
-- ============================================================================
COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  'è§£æžä¸€æ¡äº‹ä»¶å¯¹åº”çš„æ¥æºå®¢æˆ·è®°å½•ä¸Žé‡‘å®¢æˆ·ç¼–å·ï¼›æŸ¥ä¸åˆ°è¿”å›ž NULLï¼Œè¡¨ç¤ºèº«ä»½å°šæœªåˆå¹¶ã€‚ä¸¤ä¸ªæ£€æµ‹å‡½æ•°å…±ç”¨ï¼Œé¿å…å£å¾„ä¸ä¸€è‡´ã€‚';
COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'KYC éªŒè¯è§„åˆ™æ£€æµ‹ï¼šå¥—ç”¨ 8 æ¡è§„åˆ™ï¼Œæ¯æ¡è®°å½•åªè¿”å›žæœ€ä¸¥é‡çš„ä¸€æ¡å‘çŽ°ï¼ˆæŒ‰è§„åˆ™ä¼˜å…ˆçº§ã€ä¸¥é‡ç¨‹åº¦ã€è§„åˆ™åæŽ’åºå–ç¬¬ä¸€ï¼‰ã€‚æ‰¹æ¬¡ä¼  NULL è¡¨ç¤ºæ£€æŸ¥å…¨éƒ¨æ‰¹æ¬¡å¹¶å–æœ€æ–°ç‰ˆæœ¬ï¼Œç”¨äºŽåˆ¤æ–­åŽ†å²é—®é¢˜æ˜¯å¦å·²ä¿®æ­£ã€‚';
COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'AML ç­›æŸ¥è§„åˆ™æ£€æµ‹ï¼šå¥—ç”¨ 10 æ¡è§„åˆ™ï¼Œåªè¿”å›žæ¯æ¡è®°å½•æœ€ä¸¥é‡çš„å‘çŽ°ï¼ŒæŽ’åºå£å¾„ä¸Ž KYC ç‰ˆæœ¬ä¸€è‡´ã€‚æ‰¹æ¬¡ä¼  NULL è¡¨ç¤ºæ£€æŸ¥å…¨éƒ¨æ‰¹æ¬¡å¹¶å–æœ€æ–°ç‰ˆæœ¬ã€‚';
COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  'è§„åˆ™åˆ°æ¡ˆä»¶ç±»åž‹çš„å”¯ä¸€æ˜ å°„ï¼ˆæŠ¥å‘Šå£å¾„çš„å•ä¸€æ¥æºï¼‰ã€‚è¿”å›ž NULL è¡¨ç¤ºè¯¥è§„åˆ™åªç™»è®°è´¨é‡é—®é¢˜ã€ä¸å»ºæ¡ˆä»¶ï¼Œä¾‹å¦‚ LOW çº§çš„"èº«ä»½å°šæœªåˆå¹¶"æç¤ºã€‚';
COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'æŠŠä¸€æ¡æ ¡éªŒå‘çŽ°ç™»è®°ä¸ºæ•°æ®è´¨é‡é—®é¢˜ï¼ˆå†™å…¥ silver.data_quality_issueï¼‰ã€‚é—®é¢˜ç¼–å·ç”±"æ‰¹æ¬¡ + è§„åˆ™ + è®°å½•"ç”Ÿæˆï¼Œé‡è·‘åªæ›´æ–°åŒä¸€è¡Œï¼›ç™»è®°æ—¶æ¡ˆä»¶å·ç•™ç©ºï¼Œç”±æ¡ˆä»¶å¤„ç†æ­¥éª¤å›žå¡«ã€‚è¿”å›žè¯¥è§„åˆ™å¯¹åº”çš„æ¡ˆä»¶ç±»åž‹ã€‚';
COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  'æŸ¥æ‰¾æˆ–å»ºç«‹éªŒè¯æ¡ˆä»¶ï¼šåŒä¸€éªŒè¯äº‹ä»¶åŠ åŒä¸€æ¡ˆä»¶ç±»åž‹åªä¿ç•™ä¸€ä¸ªæ¡ˆä»¶ï¼Œå·²å­˜åœ¨åˆ™å¤ç”¨ã€‚è¿™æ ·åŒä¸€é—®é¢˜é‡å¤å‘çŽ°ä¸ä¼šäº§ç”Ÿä¸€å †é‡å¤æ¡ˆä»¶ã€‚';
COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  'æŸ¥æ‰¾æˆ–å»ºç«‹ AML è°ƒæŸ¥æ¡ˆä»¶ï¼Œå¤ç”¨é€»è¾‘åŒéªŒè¯æ¡ˆä»¶ã€‚ç«‹æ¡ˆæ—¶é—´å–è§¦å‘ç­›æŸ¥çš„ä¸šåŠ¡æ—¶é—´ï¼Œé¿å…é‡è·‘å¯¼è‡´è´¦é¾„è™šå¢žã€‚';
COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'æŒ‰å‘çŽ°æ‰€å±žçš„è¡¨åˆ†æ´¾åˆ°å¯¹åº”çš„å»ºæ¡ˆå‡½æ•°ï¼šKYC ç±»è¿”å›žéªŒè¯æ¡ˆä»¶ç¼–å·ï¼ŒAML ç±»è¿”å›ž NULLï¼ˆæ•°æ®è´¨é‡é—®é¢˜è¡¨åªæœ‰éªŒè¯æ¡ˆä»¶è¿™ä¸€åˆ—å¤–é”®ï¼ŒAML æ¡ˆä»¶æ— æ³•å›žå¡«åˆ°é‚£ä¸€åˆ—ï¼‰ã€‚';
COMMENT ON FUNCTION silver.customer_kyc_status(date) IS
  'æ¯ä¸ªé‡‘å®¢æˆ·ä¸€è¡Œçš„ KYC çŠ¶æ€ï¼ŒæŒ‰æŠ¥å‘Šè§„åˆ™åœ¨æŒ‡å®šåŸºå‡†æ—¥æ±‚å€¼ï¼šåªæœ‰å…¨éƒ¨æ‰€éœ€éªŒè¯æˆåŠŸä¸”æœªè¿‡æœŸã€ä¸”æ²¡æœ‰æœªç»“çš„ç›¸å…³å¼‚å¸¸æ—¶æ‰æ˜¯ VERIFIEDï¼Œå…¶ä½™ä¸º INCOMPLETEã€REVIEW_REQUIRED æˆ– UNKNOWNã€‚';
