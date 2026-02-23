# Let It Crash Audit (lib/)

Date: 2026-02-21

## Scope
- Scanned `lib/` for `try/rescue/catch` patterns.
- Focused on **catch-all** or **defensive** exception handling that violates the style guide’s “Let it Crash” principle.

## Findings Summary
- Multiple modules used broad `try/rescue` or `catch` to convert exceptions into `{:error, ...}` or to silently ignore failures.
- Several signal emitters wrapped `SignalHub.emit/3` in `rescue`, hiding signal failures.
- Some config and parsing helpers used `try/rescue` for recoverable flows where return-value APIs could be used instead.

## Non-Findings / Allowed Exceptions
- `SafeAtom` helpers: rescue `ArgumentError` only, by design.
- BDD test helpers: rescue `ConnectionAlreadyCheckedOutError` for idempotent sandbox setup.
- DB error handling in `Messages.Writer`: rescues specific DB errors only.
- Snapshot manager: rescues `Ecto.NoResultsError` for not-found behavior.

## Risk Notes
- Removing defensive rescues may surface crashes that were previously swallowed.
- Supervisors should now see these failures and restart processes as intended.
