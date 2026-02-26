# LLM 可配置设置系统 BDD 测试
# 工具拦截器和搜索配置基础测试

# ==================== 工具拦截器 ====================

[SCENARIO: BDD-INTERCEPTOR-001] TITLE: 非配置工具无需审批 TAGS: unit interceptor
  GIVEN tool_interceptor_initialized
  WHEN check_tool_approval tool_name="read_file"
  THEN approval_not_required

[SCENARIO: BDD-INTERCEPTOR-002] TITLE: 配置工具需要审批 TAGS: unit interceptor
  GIVEN tool_interceptor_initialized
  WHEN check_tool_approval tool_name="update_search_config"
  THEN approval_required reason="Configuration change"

[SCENARIO: BDD-INTERCEPTOR-003] TITLE: 预批准的配置工具可执行 TAGS: unit interceptor
  GIVEN tool_interceptor_initialized
  GIVEN tool_pre_approved tool_name="update_search_config"
  WHEN check_tool_approval tool_name="update_search_config"
  THEN approval_not_required

# ==================== 搜索配置管理 ====================

[SCENARIO: BDD-SEARCH-001] TITLE: 获取默认搜索配置 TAGS: unit search
  GIVEN search_settings_clean
  WHEN get_search_settings
  THEN search_provider_is provider="tavily"

[SCENARIO: BDD-SEARCH-002] TITLE: 更新搜索 provider TAGS: integration search
  GIVEN search_settings_clean
  WHEN update_search_provider provider="brave"
  THEN search_provider_is provider="brave"
  THEN assert_signal_emitted type="config.search.updated"

[SCENARIO: BDD-SEARCH-003] TITLE: 验证 provider 有效性 TAGS: unit search
  GIVEN search_settings_clean
  WHEN update_search_provider provider="invalid"
  THEN validation_error field="default_provider"

# ==================== 标题生成系统 ====================

[SCENARIO: BDD-TITLE-001] TITLE: 标题生成默认关闭 TAGS: unit title
  GIVEN title_settings_clean
  WHEN get_title_mode
  THEN title_mode_is mode="disabled"

[SCENARIO: BDD-TITLE-002] TITLE: 设置标题生成模式 TAGS: unit title
  GIVEN title_settings_clean
  WHEN set_title_mode mode="conversation"
  THEN title_mode_is mode="conversation"

[SCENARIO: BDD-TITLE-003] TITLE: 关闭模式不触发生成 TAGS: unit title
  GIVEN title_settings_clean
  WHEN set_title_mode mode="disabled"
  WHEN trigger_title_generation
  THEN title_generation_skipped
