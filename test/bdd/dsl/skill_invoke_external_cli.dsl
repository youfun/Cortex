# Skill invocation for external agent CLI

[SCENARIO: SKILL-CLI-001] TITLE: Parse /skill external-agent-cli TAGS: unit skills
WHEN parse_skill_command input="/skill external-agent-cli generate a refactor plan"
THEN assert_skill_command matched=true
THEN assert_skill_command name="external-agent-cli"
THEN assert_skill_command contains="Use skill external-agent-cli"
