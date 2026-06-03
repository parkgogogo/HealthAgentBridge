# Health Agent Bridge API

Base URL on the user's Mac:

```text
http://127.0.0.1:8787
```

Local loopback requests do not need a bearer token. Tailscale or LAN requests require:

```text
Authorization: Bearer health-agent-dev-token
```

## Endpoints

```text
GET /v1/status
```

Returns service status, discoverable URLs, latest report timestamps, age in seconds, device name, and remote Tailscale address.
Also includes `pendingPacketCount` and `failedPacketCount`.

```text
GET /v1/agent/context?days=14&sampleLimit=20
```

Best default endpoint for agents. Returns status, data window, `today`, `latestCompleteDay`, daily summaries, aggregates, sample type summaries, recent samples, endpoint list, and caveats.

```text
GET /v1/summary/daily?days=14
```

Returns daily summaries sorted by date. Supported fields include:

- `stepCount`
- `walkingRunningDistanceMeters`
- `activeEnergyKilocalories`
- `dietaryEnergyKilocalories`
- `dietaryProteinGrams`
- `dietaryCarbohydratesGrams`
- `dietaryFatGrams`
- `exerciseMinutes`
- `heartRateAverageBPM`
- `restingHeartRateAverageBPM`
- `sleepAsleepMinutes`
- `bodyMassKilograms`

```text
GET /v1/samples/recent?type=heartRate&limit=50
```

Returns raw samples sorted newest first. `type` is optional. Current common types are `heartRate` and `restingHeartRate`.

```text
GET /v1/workouts/recent?days=30&limit=100
```

Returns workout records sorted newest first. Fields include activity type/name, start/end timestamps, duration seconds, optional active energy in kilocalories, optional distance in meters, and source name.

```text
POST /v1/packets
```

Creates a Health Packet for iOS to write into Apple Health. Use this for user-entered body weight and food intake. Local loopback requests do not need auth; Tailscale/LAN requests need the bearer token.

Body-weight packet:

```json
{
  "type": "body_weight",
  "source": "openclaw",
  "bodyWeight": {
    "measuredAt": "2026-06-03T15:30:00Z",
    "weightKilograms": 78.4,
    "rawText": "78.4 kg"
  }
}
```

Food-intake packet:

```json
{
  "type": "food_intake",
  "source": "openclaw",
  "foodIntake": {
    "occurredAt": "2026-06-03T12:20:00Z",
    "mealType": "lunch",
    "rawText": "午饭：牛肉饭一份",
    "foodItems": [],
    "estimatedCaloriesKcal": 620,
    "proteinGrams": 32,
    "carbohydrateGrams": 78,
    "fatGrams": 18,
    "confidence": "medium"
  }
}
```

Packet statuses:

- `pending_ios_sync`: waiting for iOS to write into Apple Health.
- `written_to_healthkit`: iOS successfully wrote the packet.
- `failed`: iOS could not write the packet; see `lastError`.
- `cancelled`: manually cancelled or ignored.

```text
GET /v1/packets/pending?limit=50
GET /v1/packets/recent?limit=50
```

Lists pending or recently updated packets.

```text
GET /v1/report/latest
```

Returns the complete latest stored report envelope. Use only when the compact context is insufficient.

```text
GET /v1/openapi.json
```

Returns a compact OpenAPI path list.

## Curl Examples

```bash
curl -sS 'http://127.0.0.1:8787/v1/agent/context?days=7&sampleLimit=5' | jq .
curl -sS 'http://127.0.0.1:8787/v1/summary/daily?days=30' | jq .
curl -sS 'http://127.0.0.1:8787/v1/samples/recent?type=heartRate&limit=20' | jq .
curl -sS 'http://127.0.0.1:8787/v1/workouts/recent?days=30&limit=20' | jq .
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-weight --kg 78.4 --raw-text "78.4 kg"
python3 ~/.openclaw/skills/health-data-bridge/scripts/health_bridge.py create-food --calories 620 --raw-text "午饭：牛肉饭一份" --meal-type lunch
```
