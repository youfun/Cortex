# Tape 分支管理 BDD 测试
# 验证分支创建和隔离

[SCENARIO: TAPE-BRANCH-001] TITLE: 分支隔离 TAGS: integration tape branch
GIVEN signal_bus_is_clean
# 初始化 main 会话
WHEN signal_is_emitted type="agent.response" data='{"content":"Root Event"}' session_id="main_session"
THEN tape_should_contain_entry type="agent.response" session_id="main_session"

# 创建分支
WHEN create_tape_branch source="main_session" target="feature_branch"

# 在分支上产生新事件
WHEN signal_is_emitted type="agent.response" data='{"content":"Branch Event"}' session_id="feature_branch"

# 验证隔离性
THEN tape_should_contain_entry type="agent.response" session_id="feature_branch"
THEN tape_should_not_contain_entry type="agent.response" session_id="main_session" content="Branch Event"

# 验证继承性 (分支应该包含主干的历史吗？通常是的，或者是引用)
# 暂时假设是完全拷贝或引用。我们验证分支能看到 Root Event
THEN tape_should_contain_entry type="agent.response" session_id="feature_branch" content="Root Event"

[SCENARIO: TAPE-BRANCH-002] TITLE: 记录分支点 TAGS: integration tape branch
GIVEN signal_bus_is_clean
WHEN signal_is_emitted type="agent.response" data='{"content":"First"}' session_id="p1"
WHEN signal_is_emitted type="agent.response" data='{"content":"Second"}' session_id="p1"
# Create branch after 2 events using BranchManager
WHEN create_session_branch parent_session_id="p1" branch_id="b1"
THEN tape_branch_point_should_be branch_session_id="b1" expected=2

