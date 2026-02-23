# Extension Dynamic Registration (S8)

[SCENARIO: EXT-DYNAMIC-001] TITLE: Runtime registration of dynamic tools TAGS: extension dynamic tool s8
GIVEN signal_bus_is_clean
WHEN register_dynamic_tool tool_name="bdd_custom_tool" description="A custom tool"
THEN assert_tool_available tool_name="bdd_custom_tool"
WHEN execute_tool tool_name="bdd_custom_tool" args="{}"
THEN assert_tool_result contains="dynamic_tool_ok"
WHEN unregister_dynamic_tool tool_name="bdd_custom_tool"
THEN assert_tool_not_available tool_name="bdd_custom_tool"

[SCENARIO: EXT-DYNAMIC-002] TITLE: Unregister dynamic tool removes it from registry TAGS: extension dynamic unregister s8
GIVEN signal_bus_is_clean
WHEN register_dynamic_tool tool_name="bdd_temp_tool" description="Temporary tool"
THEN assert_tool_available tool_name="bdd_temp_tool"
WHEN unregister_dynamic_tool tool_name="bdd_temp_tool"
THEN assert_tool_not_available tool_name="bdd_temp_tool"

[SCENARIO: EXT-DYNAMIC-003] TITLE: Extension load/unload registers hooks and tools TAGS: extension load manager s8
GIVEN signal_bus_is_clean
WHEN load_extension module="JidoStudio.TestSupport.TestExtension"
THEN assert_extension_loaded module="JidoStudio.TestSupport.TestExtension"
THEN assert_hooks_registered hooks='["JidoStudio.TestSupport.TestHook"]'
THEN assert_tools_registered tools='["test_extension_tool"]'
WHEN unload_extension module="JidoStudio.TestSupport.TestExtension"
THEN assert_extension_not_loaded module="JidoStudio.TestSupport.TestExtension"
THEN assert_hooks_unregistered hooks='["JidoStudio.TestSupport.TestHook"]'
THEN assert_tools_unregistered tools='["test_extension_tool"]'
