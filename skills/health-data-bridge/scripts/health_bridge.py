#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from uuid import uuid4


DEFAULT_BASE_URL = "http://127.0.0.1:8787"
DEFAULT_TOKEN = "health-agent-dev-token"


def build_url(base_url, path, query):
    base = base_url.rstrip("/")
    if query:
        return f"{base}{path}?{urllib.parse.urlencode(query)}"
    return f"{base}{path}"


def request_json(base_url, path, query=None, token=None, method="GET", payload=None):
    url = build_url(base_url, path, query or {})
    headers = {"Accept": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    if token:
        request.add_header("Authorization", f"Bearer {token}")

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {error.code} from {url}: {body}") from error
    except urllib.error.URLError as error:
        raise SystemExit(f"Cannot reach Health Agent Bridge at {url}: {error.reason}") from error


def fetch_json(base_url, path, query=None, token=None):
    return request_json(base_url, path, query=query, token=token)


def post_json(base_url, path, payload, token=None):
    return request_json(base_url, path, token=token, method="POST", payload=payload)


def print_json(value):
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def iso_or_now(value):
    if not value:
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    normalized = value.strip()
    if normalized.endswith("Z"):
        return normalized

    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return normalized

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_food_item(raw):
    parts = [part.strip() for part in raw.split("|")]
    if not parts or not parts[0]:
        raise SystemExit("--item must start with a food name")

    def optional_float(index):
        if len(parts) <= index or not parts[index]:
            return None
        return float(parts[index])

    item = {
        "id": str(uuid4()),
        "name": parts[0],
    }
    if len(parts) > 1 and parts[1]:
        item["amountDescription"] = parts[1]
    kcal = optional_float(2)
    protein = optional_float(3)
    carbs = optional_float(4)
    fat = optional_float(5)
    if kcal is not None:
        item["estimatedCaloriesKcal"] = kcal
    if protein is not None:
        item["proteinGrams"] = protein
    if carbs is not None:
        item["carbohydrateGrams"] = carbs
    if fat is not None:
        item["fatGrams"] = fat
    return item


def main():
    parser = argparse.ArgumentParser(description="Read Apple Health data from the local Health Agent Bridge.")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("HEALTH_BRIDGE_BASE_URL", DEFAULT_BASE_URL),
        help="Bridge base URL. Defaults to HEALTH_BRIDGE_BASE_URL or http://127.0.0.1:8787.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("HEALTH_BRIDGE_TOKEN"),
        help="Bearer token for non-loopback access. Defaults to HEALTH_BRIDGE_TOKEN when set.",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="Show bridge status and latest sync timestamps.")

    context_parser = subparsers.add_parser("context", help="Fetch compact agent-oriented health context.")
    context_parser.add_argument("--days", type=int, default=14)
    context_parser.add_argument("--sample-limit", type=int, default=20)

    daily_parser = subparsers.add_parser("daily", help="Fetch daily health summaries.")
    daily_parser.add_argument("--days", type=int, default=14)

    samples_parser = subparsers.add_parser("samples", help="Fetch recent raw samples.")
    samples_parser.add_argument("--type", default=None, help="Optional sample type, such as heartRate.")
    samples_parser.add_argument("--limit", type=int, default=50)

    workouts_parser = subparsers.add_parser("workouts", help="Fetch recent workouts.")
    workouts_parser.add_argument("--days", type=int, default=30)
    workouts_parser.add_argument("--limit", type=int, default=100)

    packets_pending_parser = subparsers.add_parser("packets-pending", help="Fetch Health Packets waiting for iOS HealthKit sync.")
    packets_pending_parser.add_argument("--limit", type=int, default=50)

    packets_recent_parser = subparsers.add_parser("packets-recent", help="Fetch recently updated Health Packets.")
    packets_recent_parser.add_argument("--limit", type=int, default=50)

    create_weight_parser = subparsers.add_parser("create-weight", help="Create a body-weight packet for iOS to write into Apple Health.")
    create_weight_parser.add_argument("--kg", type=float, required=True, help="Body weight in kilograms.")
    create_weight_parser.add_argument("--measured-at", default=None, help="ISO 8601 timestamp. Defaults to now.")
    create_weight_parser.add_argument("--raw-text", default=None, help="Original user wording, if available.")
    create_weight_parser.add_argument("--note", default=None)
    create_weight_parser.add_argument("--packet-id", default=None)

    create_food_parser = subparsers.add_parser("create-food", help="Create a food-intake packet for iOS to write into Apple Health.")
    create_food_parser.add_argument("--calories", type=float, required=True, help="Estimated dietary energy in kcal.")
    create_food_parser.add_argument("--raw-text", required=True, help="Original user meal description.")
    create_food_parser.add_argument("--occurred-at", default=None, help="ISO 8601 timestamp. Defaults to now.")
    create_food_parser.add_argument("--meal-type", default=None, help="Optional meal label, such as breakfast/lunch/dinner/snack.")
    create_food_parser.add_argument("--protein", type=float, default=None, help="Protein in grams.")
    create_food_parser.add_argument("--carbs", type=float, default=None, help="Carbohydrates in grams.")
    create_food_parser.add_argument("--fat", type=float, default=None, help="Fat in grams.")
    create_food_parser.add_argument("--confidence", choices=["low", "medium", "high"], default="medium")
    create_food_parser.add_argument("--estimation-notes", default=None)
    create_food_parser.add_argument("--packet-id", default=None)
    create_food_parser.add_argument(
        "--item",
        action="append",
        default=[],
        help="Optional item as name|amount|kcal|protein_g|carbs_g|fat_g. Can be repeated.",
    )

    subparsers.add_parser("latest", help="Fetch the complete latest report envelope.")
    subparsers.add_parser("openapi", help="Fetch the compact OpenAPI path list.")

    args = parser.parse_args()
    token = args.token

    if args.command == "status":
        payload = fetch_json(args.base_url, "/v1/status", token=token)
    elif args.command == "context":
        payload = fetch_json(
            args.base_url,
            "/v1/agent/context",
            {"days": args.days, "sampleLimit": args.sample_limit},
            token=token,
        )
    elif args.command == "daily":
        payload = fetch_json(args.base_url, "/v1/summary/daily", {"days": args.days}, token=token)
    elif args.command == "samples":
        query = {"limit": args.limit}
        if args.type:
            query["type"] = args.type
        payload = fetch_json(args.base_url, "/v1/samples/recent", query, token=token)
    elif args.command == "workouts":
        payload = fetch_json(
            args.base_url,
            "/v1/workouts/recent",
            {"days": args.days, "limit": args.limit},
            token=token,
        )
    elif args.command == "packets-pending":
        payload = fetch_json(args.base_url, "/v1/packets/pending", {"limit": args.limit}, token=token)
    elif args.command == "packets-recent":
        payload = fetch_json(args.base_url, "/v1/packets/recent", {"limit": args.limit}, token=token)
    elif args.command == "create-weight":
        body_weight = {
            "measuredAt": iso_or_now(args.measured_at),
            "weightKilograms": args.kg,
        }
        if args.raw_text:
            body_weight["rawText"] = args.raw_text
        if args.note:
            body_weight["note"] = args.note

        request = {
            "type": "body_weight",
            "source": "openclaw",
            "bodyWeight": body_weight,
        }
        if args.packet_id:
            request["packetId"] = args.packet_id
        payload = post_json(args.base_url, "/v1/packets", request, token=token)
    elif args.command == "create-food":
        food_items = [parse_food_item(item) for item in args.item]
        if not food_items:
            food_items = [
                {
                    "id": str(uuid4()),
                    "name": args.raw_text,
                    "estimatedCaloriesKcal": args.calories,
                    "proteinGrams": args.protein,
                    "carbohydrateGrams": args.carbs,
                    "fatGrams": args.fat,
                }
            ]

        food_intake = {
            "occurredAt": iso_or_now(args.occurred_at),
            "rawText": args.raw_text,
            "foodItems": food_items,
            "estimatedCaloriesKcal": args.calories,
            "confidence": args.confidence,
        }
        if args.meal_type:
            food_intake["mealType"] = args.meal_type
        if args.protein is not None:
            food_intake["proteinGrams"] = args.protein
        if args.carbs is not None:
            food_intake["carbohydrateGrams"] = args.carbs
        if args.fat is not None:
            food_intake["fatGrams"] = args.fat
        if args.estimation_notes:
            food_intake["estimationNotes"] = args.estimation_notes

        request = {
            "type": "food_intake",
            "source": "openclaw",
            "foodIntake": food_intake,
        }
        if args.packet_id:
            request["packetId"] = args.packet_id
        payload = post_json(args.base_url, "/v1/packets", request, token=token)
    elif args.command == "latest":
        payload = fetch_json(args.base_url, "/v1/report/latest", token=token)
    elif args.command == "openapi":
        payload = fetch_json(args.base_url, "/v1/openapi.json", token=token)
    else:
        parser.error(f"Unknown command: {args.command}")

    print_json(payload)


if __name__ == "__main__":
    main()
