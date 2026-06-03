#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/skills/health-tracker"
OPENCLAW_HOME="${OPENCLAW_HOME:-${HOME}/.openclaw}"
TARGET_DIR="${OPENCLAW_HOME}/skills/health-tracker"
OLD_TARGET_DIR="${OPENCLAW_HOME}/skills/health-data-bridge"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Missing source skill: ${SOURCE_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${TARGET_DIR}")"
rsync -a --delete "${SOURCE_DIR}/" "${TARGET_DIR}/"
chmod +x "${TARGET_DIR}/scripts/health_tracker.py"

if [[ -d "${OLD_TARGET_DIR}" && "${OLD_TARGET_DIR}" != "${TARGET_DIR}" ]]; then
  rm -rf "${OLD_TARGET_DIR}"
fi

echo "Installed health-tracker skill to ${TARGET_DIR}"
