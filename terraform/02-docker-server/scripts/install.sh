#!/bin/bash
# =============================================================================
# docker-node1 bootstrap script
# Runs ONCE on the first boot, as root, through cloud-init (EC2 user_data).
# Terraform's templatefile() fills in the template values (hostname, timezone,
# deploy_user, app_dir, internal_public_key) before the server starts.
#
# Installs: hostname, timezone, Docker (enabled on every boot),
#           deploy user for Ansible (SSH key only), app folder, SSH hardening
# Logs:     /var/log/bootstrap.log (also /var/log/cloud-init-output.log)
# Done:     /var/log/bootstrap-complete
# =============================================================================

set -euo pipefail

LOG=/var/log/bootstrap.log
MARKER=/var/log/bootstrap-complete
DEPLOY_USER="${deploy_user}"
APP_DIR="${app_dir}"

# Send all output to the log file and to the console log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Safe to run again: stop if setup already finished
if [ -f "$MARKER" ]; then
  log "Already bootstrapped, nothing to do"
  exit 0
fi

log "Starting docker-node1 bootstrap"

# ---------- 1. Identity: hostname and timezone (as in the project guide) ----------
hostnamectl set-hostname "${hostname}"
timedatectl set-timezone "${timezone}"
log "Hostname: $(hostname), timezone: ${timezone}"

# ---------- 2. Operating system updates ----------
dnf -y update
log "System packages updated"

# ---------- 3. Docker: install, start now, start on every boot ----------
dnf -y install docker
systemctl enable --now docker
docker info > /dev/null
log "Installed $(docker --version), service: $(systemctl is-active docker)"

# ---------- 4. Deploy user for Ansible (itadmin in the project guide) ----------
if ! id "$DEPLOY_USER" > /dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi

# No password at all: this user can only log in with the internal SSH key
passwd -l "$DEPLOY_USER" > /dev/null

# May run Docker without sudo
usermod -aG docker "$DEPLOY_USER"

# Passwordless sudo, so Ansible can use "become" without a password prompt
SUDOERS_FILE="/etc/sudoers.d/90-$DEPLOY_USER"
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" > /dev/null

# Accept the internal key (the ansible server holds the private half)
DEPLOY_HOME="/home/$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$DEPLOY_HOME/.ssh"
echo "${internal_public_key}" > "$DEPLOY_HOME/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh/authorized_keys"
chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys"
log "Deploy user ready: $(id "$DEPLOY_USER")"

# ---------- 5. Application folder (as in the project guide: /opt/docker) ----------
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"
log "Application folder ready: $APP_DIR"

# ---------- 6. SSH hardening: keys only, no root login ----------
# OpenSSH uses the FIRST value it reads, so this file is named 00-* to be read first
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf
sshd -t
systemctl reload sshd
log "SSH hardened: password login and root login disabled"

# ---------- 7. Done marker (used to verify the bootstrap) ----------
cat > "$MARKER" <<EOF
server=$(hostname)
finished=$(date '+%Y-%m-%d %H:%M:%S %Z')
docker=$(docker --version | awk '{print $3}' | tr -d ',')
docker_service=$(systemctl is-active docker)
deploy_user=$DEPLOY_USER
app_dir=$APP_DIR
EOF

log "docker-node1 bootstrap complete"
