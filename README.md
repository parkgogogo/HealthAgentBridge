# HealthAgentBridge

Personal Apple Health bridge for local AI agents.

## What it contains

- `HealthReporter`: iOS app. It has one main switch, requests HealthKit read access, registers HealthKit background delivery, collects recent daily summaries, and posts reports to the Mac bridge.
- `HealthBridgeMac`: macOS menu bar app. It listens on port `8787`, advertises `_healthbridge._tcp` as a fallback, stores the latest report in Application Support, and exposes local HTTP endpoints for agents.

## Sync design

The iPhone app first posts to the Mac through Tailscale MagicDNS:

```text
http://your-mac.tailnet.ts.net:8787/v1/ingest
```

If MagicDNS fails, it tries the Mac's current Tailscale IPv4 address:

```text
http://100.64.0.1:8787/v1/ingest
```

If both Tailscale targets fail, it falls back to Bonjour discovery on the local network. Failed uploads are queued locally on the iPhone and retried before the next report is sent.

## Private configuration

Public defaults live in `Config/HealthBridge.xcconfig`. Copy the example file and
fill in your private values before building for your own devices:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

`Config/Local.xcconfig` is ignored by git. Set:

```text
HEALTH_BRIDGE_TAILNET_HOST = your-mac.tailnet.ts.net
HEALTH_BRIDGE_TAILNET_IPV4 = 100.64.0.1
HEALTH_BRIDGE_SHARED_TOKEN = replace-with-a-random-token
HEALTH_BRIDGE_DEVELOPMENT_TEAM = YOURTEAMID
HEALTH_REPORTER_BUNDLE_IDENTIFIER = com.example.HealthReporter
HEALTH_BRIDGE_MAC_BUNDLE_IDENTIFIER = com.example.HealthBridgeMac
```

## Endpoints

Run the macOS app first, then open:

```sh
curl http://127.0.0.1:8787/v1/status
curl 'http://127.0.0.1:8787/v1/agent/context?days=14&sampleLimit=20'
curl 'http://127.0.0.1:8787/v1/summary/daily?days=14'
curl 'http://127.0.0.1:8787/v1/samples/recent?type=heartRate&limit=50'
curl 'http://127.0.0.1:8787/v1/workouts/recent?days=30&limit=100'
curl http://127.0.0.1:8787/v1/report/latest
curl http://127.0.0.1:8787/v1/openapi.json
```

For agents, prefer `/v1/agent/context`: it includes freshness, daily summaries,
aggregate metrics, latest complete day, sample type coverage, recent samples,
recent workouts, and the endpoint list in one JSON response. The current day can
be partial, so health planning agents should prefer `latestCompleteDay` for daily
conclusions.

OpenClaw skill installed locally:

```sh
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py context --days 14
```

The iOS app uses this shared token when posting to the Mac:

```text
HEALTH_BRIDGE_SHARED_TOKEN
```

## Development notes

- Open `HealthAgentBridge.xcodeproj` in Xcode.
- Select your Apple Account / Personal Team for the `HealthReporter` iOS target, or set `HEALTH_BRIDGE_DEVELOPMENT_TEAM` in `Config/Local.xcconfig`.
- Run `HealthBridgeMac` on the Mac first. It appears in the menu bar instead of the Dock.
- Run `HealthReporter` on your physical iPhone, not only the simulator.
- HealthKit background delivery requires real-device HealthKit authorization. If you force-quit the iPhone app from the app switcher, iOS may stop background delivery until you open it again.
- Keep Tailscale connected on both the Mac and iPhone. MagicDNS should resolve your configured `HEALTH_BRIDGE_TAILNET_HOST` from the iPhone.
