[SCENARIO: AUDIT-NOISE-001] TITLE: 过滤内存操作信号 TAGS: integration audit
  GIVEN signal_bus_is_clean
  WHEN signal_is_emitted type="memory.observation" data='{"foo":"bar"}'
  THEN history_file_should_not_contain type="memory.observation"

[SCENARIO: AUDIT-NOISE-003] TITLE: 过滤知识图谱信号 TAGS: integration audit
  GIVEN signal_bus_is_clean
  WHEN signal_is_emitted type="kg.node.created" data='{"id":"node1"}'
  THEN history_file_should_not_contain type="kg.node.created"

[SCENARIO: AUDIT-NOISE-004] TITLE: 过滤 UI 交互信号 TAGS: integration audit
  GIVEN signal_bus_is_clean
  WHEN signal_is_emitted type="ui.button.clicked" data='{"id":"save"}'
  THEN history_file_should_not_contain type="ui.button.clicked"
