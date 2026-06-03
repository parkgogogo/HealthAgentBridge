#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/skills/health-data-bridge"
OPENCLAW_HOME="${OPENCLAW_HOME:-${HOME}/.openclaw}"
TARGET_DIR="${OPENCLAW_HOME}/skills/health-data-bridge"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Missing source skill: ${SOURCE_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${TARGET_DIR}")"
rsync -a --delete "${SOURCE_DIR}/" "${TARGET_DIR}/"
chmod +x "${TARGET_DIR}/scripts/health_bridge.py"

echo "Installed health-data-bridge skill to ${TARGET_DIR}"
