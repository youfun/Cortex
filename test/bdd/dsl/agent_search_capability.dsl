# Agent Search Capability

[SCENARIO: SEARCH-001] TITLE: Web search tool returns formatted results TAGS: search web_search
GIVEN signal_bus_is_clean
WHEN execute_tool tool_name='web_search' args='{"query":"elixir genserver"}'
THEN assert_tool_result contains='URL:'

[SCENARIO: SEARCH-002] TITLE: SearchExtension loads successfully TAGS: search extension load
GIVEN signal_bus_is_clean
WHEN load_extension module='Cortex.Extensions.SearchExtension'
THEN assert_extension_loaded module='Cortex.Extensions.SearchExtension'
THEN assert_tools_registered tools='["web_search"]'
