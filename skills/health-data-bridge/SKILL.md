---
name: health-data-bridge
description: Access the user's local Apple Health data through the Health Agent Bridge HTTP service on macOS. Use when the user asks about recent health metrics, Apple Health data, steps, sleep, heart rate, activity, exercise, health trends, or wants health data summarized for planning. Always fetch fresh data from the bridge instead of relying on memory.
---

# Health Data Bridge

## Quick Start

Fetch the compact agent context first:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py context --days 14 --sample-limit 20
```

Use this endpoint data as the source of truth for health analysis. The bridge runs on the user's Mac at `http://127.0.0.1:8787`.

## Workflow

1. Check freshness when needed:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py status
```

2. Read the compact context for most tasks:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py context --days 14
```

3. For trend calculations, fetch daily summaries with an explicit window:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py daily --days 30
```

4. For raw heart-rate inspection, fetch recent samples:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py samples --type heartRate --limit 100
```

5. For logged workouts, fetch recent workouts:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py workouts --days 30 --limit 100
```

6. To record body weight or food intake, create a Health Packet on the Mac. The iOS app will later write the packet into Apple Health and acknowledge it:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-weight --kg 78.4 --raw-text "78.4 kg"
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-food --calories 620 --raw-text "午饭：牛肉饭一份" --meal-type lunch --protein 32 --carbs 78 --fat 18 --confidence medium
```

7. After creating packets, check whether iOS has written them into Apple Health:

```bash
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py packets-pending
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py packets-recent
```

## Interpretation Rules

- Prefer `latestCompleteDay` over `today` for daily conclusions because the current day may be partial.
- Check `latestReceivedAgeSeconds` and `latestGeneratedAgeSeconds`; mention stale data if the latest report is not recent enough for the user's question.
- Preserve units. Distance summaries expose meters in daily rows and kilometers in aggregate fields. Sleep summary rows expose minutes; aggregate sleep is hours.
- Treat workouts as HealthKit `HKWorkout` records. They are Apple Health data, but they are separate sample objects from quantity summaries such as exercise minutes.
- Treat Apple Health as the durable health-data source. For user-entered food and weight, create Health Packets through the Mac bridge; do not assume they are visible in daily summaries until `packets-recent` shows `written_to_healthkit` and a fresh iOS report has arrived.
- For weight loss analysis, do not call `dietaryEnergyKilocalories - activeEnergyKilocalories` a true calorie deficit. Active energy is only exercise/activity energy; total daily energy expenditure requires a separate BMR/TDEE estimate.
- Do not send health data to external services unless the user explicitly asks.
- If the bridge is unavailable, say the local Mac service is not reachable and suggest opening the HealthBridgeMac menu bar app.

## Resources

- API details: `references/api.md`
- Script wrapper: `scripts/health_bridge.py`
