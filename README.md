# HealthAgentBridge

Personal Apple Health bridge for local AI agents.

## What it contains

- `HealthReporter`: iOS app. It has one main switch, requests HealthKit read/write access, registers HealthKit background delivery, collects recent daily summaries, posts reports to the Mac bridge, and writes supported Health Packets into Apple Health.
- `HealthBridgeMac`: macOS menu bar app. It listens on port `8787`, advertises `_healthbridge._tcp` as a fallback, stores the latest report plus Health Packet queue in Application Support, and exposes local HTTP endpoints for agents.

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

Agent-entered body weight and food intake use the reverse direction:

1. OpenClaw or another local agent creates a Health Packet on the Mac with `POST /v1/packets`.
2. The iPhone app fetches pending packets after a successful report upload.
3. The iPhone writes supported packets into Apple Health through HealthKit.
4. The iPhone acknowledges the packet as `written_to_healthkit` or `failed`.
5. The next report upload makes the new Apple Health values visible to agents.

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
curl 'http://127.0.0.1:8787/v1/packets/pending?limit=50'
curl 'http://127.0.0.1:8787/v1/packets/recent?limit=50'
curl http://127.0.0.1:8787/v1/report/latest
curl http://127.0.0.1:8787/v1/openapi.json
```

For agents, prefer `/v1/agent/context`: it includes freshness, daily summaries,
aggregate metrics, latest complete day, sample type coverage, recent samples,
recent workouts, and the endpoint list in one JSON response. The current day can
be partial, so health planning agents should prefer `latestCompleteDay` for daily
conclusions.

OpenClaw skill is packaged in this repository at `skills/health-data-bridge`.
Install or refresh it into `~/.openclaw` with:

```sh
./scripts/install_openclaw_skill.sh
```

After installation, OpenClaw can use:

```sh
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py context --days 14
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-weight --kg 78.4 --raw-text "78.4 kg"
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-food --calories 620 --raw-text "午饭：牛肉饭一份" --meal-type lunch
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
