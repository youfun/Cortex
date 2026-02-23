# Model Route Warnings Fix Analysis (2026-02-21)

## Goal
Eliminate compile warnings caused by invalid LiveView route paths and an unused alias.

## Findings
- Router defines model routes under `/settings/models/*`.
- `ModelLive.Index` referenced `/models/*` which does not exist.
- `SettingsLive.ModelsComponent` imported `LlmModel` but did not use it.

## Plan
- Update all `~p"/models"` usages in `ModelLive.Index` to `/settings/models` equivalents.
- Remove unused alias in `SettingsLive.ModelsComponent`.
