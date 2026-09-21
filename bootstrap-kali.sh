#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/vaishnavucv/ctf2026.git}"
SOURCE_DIR=""
RUNTIME_DIR="${RUNTIME_DIR:-/opt/ctf2026-kali-lab}"
CTF_PORTS=(2222 5678 6200 6379 8080)
REMOVE_SOURCE=0

if [[ ${1:-} == "--remove-source" ]]; then
  REMOVE_SOURCE=1
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: sudo bash bootstrap-kali.sh [--remove-source]" >&2
  exit 2
fi

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash bootstrap-kali.sh" >&2
  exit 1
fi

if ! ip link show eth0 >/dev/null 2>&1; then
  echo "This Kali VM has no eth0 interface." >&2
  echo "Available interfaces:" >&2
  ip -brief link >&2
  exit 1
fi

TARGET_IP="$(ip -4 -o addr show dev eth0 scope global | awk '{split($4, address, "/"); print address[1]; exit}')"
if [[ -z ${TARGET_IP} ]]; then
  echo "eth0 has no IPv4 address. Connect the VM network and retry." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing Docker and classroom utilities when missing"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git docker.io nmap netcat-openbsd python3

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

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
else
  COMPOSE=(docker-compose)
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [[ -f "${SCRIPT_DIR}/Dockerfile" && -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
  SOURCE_DIR="${SCRIPT_DIR}"
else
  SOURCE_DIR="/opt/ctf2026-source"
  log "Downloading the CTF source"
  if [[ -d "${SOURCE_DIR}/.git" ]]; then
    git -C "${SOURCE_DIR}" pull --ff-only
  else
    rm -rf "${SOURCE_DIR}"
    git clone --depth 1 "${REPO_URL}" "${SOURCE_DIR}"
  fi
fi

log "Preparing an isolated runtime copy for this Kali VM"
STAGING_DIR="${RUNTIME_DIR}.new"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
tar -C "${SOURCE_DIR}" --exclude=.git -cf - . | tar -C "${STAGING_DIR}" -xf -

TARGET_IP="${TARGET_IP}" STAGING_DIR="${STAGING_DIR}" python3 - <<'PY'
import os
import re
from pathlib import Path

target_ip = os.environ["TARGET_IP"]
root = Path(os.environ["STAGING_DIR"])
for relative in ("shell.php", "freemedia/uploads/shell.php"):
    path = root / relative
    text = path.read_text()
    text, count = re.subn(r"\$ip\s*=\s*'[^']+';", f"$ip = '{target_ip}';", text, count=1)
    if count != 1:
        raise SystemExit(f"Could not configure callback address in {path}")
    path.write_text(text)
PY

printf 'LAB_BIND_IP=%s\n' "${TARGET_IP}" > "${STAGING_DIR}/.env"

if [[ -d ${RUNTIME_DIR} ]]; then
  (cd "${RUNTIME_DIR}" && "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true)
  rm -rf "${RUNTIME_DIR}"
fi
mv "${STAGING_DIR}" "${RUNTIME_DIR}"

log "Building and starting the local CTF target on eth0 (${TARGET_IP})"
cd "${RUNTIME_DIR}"
"${COMPOSE[@]}" up -d --build

log "Waiting for the target health check"
for attempt in $(seq 1 90); do
  state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' vsftpd-234-ctf 2>/dev/null || true)"
  if [[ ${state} == healthy ]]; then
    break
  fi
  if [[ ${attempt} -eq 90 ]]; then
    "${COMPOSE[@]}" ps
    "${COMPOSE[@]}" logs --tail 100
    echo "The CTF target did not become healthy." >&2
    exit 1
  fi
  sleep 2
done

if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
  usermod -aG docker "${SUDO_USER}" || true
fi

if [[ ${REMOVE_SOURCE} -eq 1 ]]; then
  if [[ ${SOURCE_DIR} == "/" || ${SOURCE_DIR} == "${RUNTIME_DIR}" || ! -d "${SOURCE_DIR}/.git" ]]; then
    echo "Refusing to remove an unsafe or unverified source directory: ${SOURCE_DIR}" >&2
    exit 1
  fi
  log "Removing the cloned source repository after the successful build"
  rm -rf -- "${SOURCE_DIR}"
fi

"${COMPOSE[@]}" ps
cat <<EOF

The isolated CTF target is ready inside this Kali VM.

Target and callback IP: ${TARGET_IP} (eth0)
Runtime directory:      ${RUNTIME_DIR}

Initial scan:
  sudo nmap -Pn -sV -p- ${TARGET_IP}

Focused vulnerability scan:
  sudo nmap -Pn -sV -p2222,5678,6379,8080 --script=vuln ${TARGET_IP}

Directory discovery:
  gobuster dir -u http://${TARGET_IP}:8080/ -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt

PHP callback listener:
  nc -lvnp 4444

Metasploit uses the same address for both sides:
  RHOSTS=${TARGET_IP}  RPORT=5678  LHOST=${TARGET_IP}

TCP 6200 is closed until the FTP backdoor is triggered.
Restart the target with: sudo docker restart vsftpd-234-ctf
EOF
