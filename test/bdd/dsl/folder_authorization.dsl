# Folder Authorization BDD Test
# Verifies that folder-level authorization restricts file access.

[SCENARIO: FOLDER-AUTH-001] TITLE: Unrestricted mode allows all paths TAGS: integration security
  GIVEN signal_bus_is_clean
  WHEN check_folder_access agent_id="agent_unr" path="src/main.ex" project_root="/tmp/test" mode="unrestricted"
  THEN assert_folder_access result="ok"

[SCENARIO: FOLDER-AUTH-002] TITLE: Whitelist mode blocks unauthorized paths TAGS: integration security
  GIVEN signal_bus_is_clean
  GIVEN add_authorized_folder agent_id="agent_wl" folder="src"
  WHEN check_folder_access agent_id="agent_wl" path="docs/readme.md" project_root="/tmp/test" mode="whitelist"
  THEN assert_folder_access result="denied"

[SCENARIO: FOLDER-AUTH-003] TITLE: Whitelist mode allows authorized paths TAGS: integration security
  GIVEN signal_bus_is_clean
  GIVEN add_authorized_folder agent_id="agent_wl2" folder="src"
  WHEN check_folder_access agent_id="agent_wl2" path="src/app.ex" project_root="/tmp/test" mode="whitelist"
  THEN assert_folder_access result="ok"

[SCENARIO: FOLDER-AUTH-004] TITLE: Remove folder reverts to unrestricted when empty TAGS: integration security
  GIVEN signal_bus_is_clean
  GIVEN add_authorized_folder agent_id="agent_rm" folder="src"
  WHEN remove_authorized_folder agent_id="agent_rm" folder="src"
  WHEN check_folder_access agent_id="agent_rm" path="docs/readme.md" project_root="/tmp/test" mode="unrestricted"
  THEN assert_folder_access result="ok"
