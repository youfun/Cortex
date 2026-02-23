[SCENARIO: SIGNAL-CORE-001] TITLE: Automatic payload wrapping and validation
  GIVEN signal_bus_is_clean
  # Emit a minimal signal, expecting the system to fill in default provider/actor etc.
  LET event_data = '{"value": 1}'
  WHEN signal_is_emitted type="test.event.emit" data=$event_data session_id="sig_test"
  
  # Check if the signal was recorded with the wrapper fields
  THEN assert_signal_data type="test.event.emit" path="provider" expected="bdd"
  THEN assert_signal_data type="test.event.emit" path="actor" expected="tester"
  THEN assert_signal_data type="test.event.emit" path="payload.value" expected="1"

[SCENARIO: SIGNAL-CORE-002] TITLE: Signal subscription and reception
  GIVEN signal_bus_is_clean
  # We test this by emitting a signal and verifying it appears in history
  # which implies the recorder (a subscriber) received it.
  
  LET data = '{"msg": "hello"}'
  WHEN signal_is_emitted type="agent.chat.request" data=$data session_id="sig_test"
  
  THEN history_file_should_contain type="agent.chat.request"
  THEN assert_signal_data type="agent.chat.request" path="payload.msg" expected="hello"
