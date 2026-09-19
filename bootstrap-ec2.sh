#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-git@github.com:vaishnavucv/ctf2026.git}"
REPO_HTTPS_URL="${REPO_HTTPS_URL:-https://github.com/vaishnavucv/ctf2026.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ctf2026}"
CTF_PORTS=(2222 5678 6200 6379 8080)

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root: sudo bash bootstrap-ec2.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing Git, Docker Engine, and required utilities"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git docker.io

if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-v2 || \
    apt-get install -y --no-install-recommends docker-compose-plugin
fi

systemctl enable --now docker

if [[ -n ${CTF_SSH_USER:-} || -n ${CTF_SSH_PASSWORD:-} ]]; then
  if [[ -z ${CTF_SSH_USER:-} || -z ${CTF_SSH_PASSWORD:-} ]]; then
    echo "Set both CTF_SSH_USER and CTF_SSH_PASSWORD, or neither." >&2
    exit 1
  fi
  if [[ ! ${CTF_SSH_USER} =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "CTF_SSH_USER is not a valid Linux username." >&2
    exit 1
  fi

  log "Configuring the requested SSH login user"
  if ! id "${CTF_SSH_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "${CTF_SSH_USER}"
  fi
  echo "${CTF_SSH_USER}:${CTF_SSH_PASSWORD}" | chpasswd
  usermod -aG sudo,docker "${CTF_SSH_USER}"
  printf '%s ALL=(ALL:ALL) ALL\n' "${CTF_SSH_USER}" > "/etc/sudoers.d/${CTF_SSH_USER}"
  chmod 0440 "/etc/sudoers.d/${CTF_SSH_USER}"
  visudo -cf "/etc/sudoers.d/${CTF_SSH_USER}"
  cat > /etc/ssh/sshd_config.d/99-ctf-password-login.conf <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF
  systemctl restart ssh
fi

log "Cloning or updating the CTF repository"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    git -C "${INSTALL_DIR}" -c http.extraHeader="Authorization: Bearer ${GITHUB_TOKEN}" pull --ff-only
  else
    git -C "${INSTALL_DIR}" pull --ff-only
  fi
else
  if [[ -e "${INSTALL_DIR}" ]]; then
    echo "${INSTALL_DIR} exists but is not a Git checkout." >&2
    exit 1
  fi
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    git -c http.extraHeader="Authorization: Bearer ${GITHUB_TOKEN}" clone "${REPO_HTTPS_URL}" "${INSTALL_DIR}"
  else
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi
fi

log "Building and starting the CTF target"
cd "${INSTALL_DIR}"
docker compose up -d --build

log "Waiting for the target health check"
for attempt in $(seq 1 90); do
  state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' vsftpd-234-ctf 2>/dev/null || true)"
  if [[ ${state} == healthy ]]; then
    break
  fi
  if [[ ${attempt} -eq 90 ]]; then
    docker compose ps
    docker compose logs --tail 100
    echo "The target did not become healthy." >&2
    exit 1
  fi
  sleep 2
done

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  log "Allowing CTF ports through UFW"
  ufw allow 22/tcp
  for port in "${CTF_PORTS[@]}"; do
    ufw allow "${port}/tcp"
  done
fi

TOKEN="$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token 2>/dev/null || true)"
PUBLIC_IP=""
if [[ -n ${TOKEN} ]]; then
  PUBLIC_IP="$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
fi
if [[ -z ${PUBLIC_IP} ]]; then
  PUBLIC_IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
fi
if [[ -z ${PUBLIC_IP} ]]; then
  PUBLIC_IP="<EC2_PUBLIC_IP>"
fi

docker compose ps
cat <<EOF

CTF target is ready.

Attack target IP: ${PUBLIC_IP}
SSH:               ${PUBLIC_IP}:22
OpenSSH decoy:     ${PUBLIC_IP}:2222
Vulnerable FTP:    ${PUBLIC_IP}:5678
Backdoor shell:    ${PUBLIC_IP}:6200 (closed until FTP trigger)
Redis decoy:       ${PUBLIC_IP}:6379
FreeMedia web:     http://${PUBLIC_IP}:8080/
Hidden portal:     http://${PUBLIC_IP}:8080/freemedia/

AWS security group inbound TCP ports required from the student network:
22, 2222, 5678, 6200, 6379, 8080

Student scan:
nmap -Pn -sV -p- ${PUBLIC_IP}
EOF
