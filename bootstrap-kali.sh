#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash bootstrap-kali.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

printf '\nInstalling Docker and the local CTF tools...\n'
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git docker.io nmap netcat-openbsd psmisc python3

if ! docker compose version >/dev/null 2>&1 && ! docker-compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-v2 || \
    apt-get install -y --no-install-recommends docker-compose-plugin || \
    apt-get install -y --no-install-recommends docker-compose
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker
else
  service docker start
fi

exec bash "${SCRIPT_DIR}/start-kali.sh"
