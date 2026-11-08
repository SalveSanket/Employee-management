#!/bin/bash
# =============================================================================
# ansible server bootstrap script
# Runs ONCE on the first boot, as root, through cloud-init (EC2 user_data).
# Terraform's templatefile() fills in the template values (hostname, timezone,
# region, deploy_user, private_key_param, internal_public_key, docker_host_name,
# docker_host_ip, project_dir, staging_dir) before the server starts.
#
# Installs: hostname, timezone, Ansible, deploy user (SSH key only),
#           internal private key from SSM, inventory + ansible.cfg,
#           staging folder for Jenkins uploads, SSH hardening
# Logs:     /var/log/bootstrap.log (also /var/log/cloud-init-output.log)
# Done:     /var/log/bootstrap-complete
# =============================================================================

set -euo pipefail

LOG=/var/log/bootstrap.log
MARKER=/var/log/bootstrap-complete
DEPLOY_USER="${deploy_user}"
DEPLOY_HOME="/home/$DEPLOY_USER"
PROJECT_DIR="${project_dir}"
STAGING_DIR="${staging_dir}"
DOCKER_HOST_NAME="${docker_host_name}"
DOCKER_HOST_IP="${docker_host_ip}"

# Send all output to the log file and to the console log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Run a command as the deploy user, with the correct home folder
as_deploy() { sudo -H -u "$DEPLOY_USER" "$@"; }

# Safe to run again: stop if setup already finished
if [ -f "$MARKER" ]; then
  log "Already bootstrapped, nothing to do"
  exit 0
fi

log "Starting ansible bootstrap"

# ---------- 1. Identity: hostname and timezone (as in the project guide) ----------
hostnamectl set-hostname "${hostname}"
timedatectl set-timezone "${timezone}"
log "Hostname: $(hostname), timezone: ${timezone}"

# ---------- 2. Operating system updates and Ansible ----------
dnf -y update
dnf -y install ansible-core
command -v aws > /dev/null || dnf -y install awscli-2

# Fail loudly if the installed Ansible does not run.
# (sed -n 1p instead of head -1: with "pipefail", head can make the pipeline fail)
ansible-playbook --version > /dev/null
ANSIBLE_VERSION_LINE="$(ansible --version | sed -n 1p)"
log "Installed $ANSIBLE_VERSION_LINE"

# ---------- 3. Deploy user (itadmin in the project guide) ----------
if ! id "$DEPLOY_USER" > /dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi

# No password at all: SSH key login only
passwd -l "$DEPLOY_USER" > /dev/null

# Passwordless sudo (as in the project guide)
SUDOERS_FILE="/etc/sudoers.d/90-$DEPLOY_USER"
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" > /dev/null

install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$DEPLOY_HOME/.ssh"

# Accept the internal key, so Jenkins (which holds the private half) can log in
echo "${internal_public_key}" > "$DEPLOY_HOME/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh/authorized_keys"
chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys"
log "Deploy user ready: $(id "$DEPLOY_USER")"

# ---------- 4. Internal private key from SSM (never in code or user_data) ----------
# The IAM role allows reading only this one parameter. A new role can take a
# short time to become usable, so retry for up to 2 minutes.
KEY_FILE="$DEPLOY_HOME/.ssh/id_rsa"
TMP_KEY="$(mktemp)"
chmod 600 "$TMP_KEY"

for attempt in $(seq 1 24); do
  if aws ssm get-parameter \
      --region "${region}" \
      --name "${private_key_param}" \
      --with-decryption \
      --query Parameter.Value \
      --output text > "$TMP_KEY" 2> /dev/null; then
    break
  fi
  log "Waiting for permission to read the key (attempt $attempt/24)"
  sleep 5
done

# Check the downloaded file really is a valid private key
if ! ssh-keygen -y -f "$TMP_KEY" > /dev/null 2>&1; then
  rm -f "$TMP_KEY"
  log "ERROR: could not read a valid private key from SSM parameter ${private_key_param}"
  exit 1
fi

install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$TMP_KEY" "$KEY_FILE"
rm -f "$TMP_KEY"
echo "${internal_public_key}" > "$KEY_FILE.pub"
chown "$DEPLOY_USER:$DEPLOY_USER" "$KEY_FILE.pub"
chmod 644 "$KEY_FILE.pub"
log "Internal private key installed: $KEY_FILE (mode 600)"

# ---------- 5. Name resolution for docker-node1 (as in the project guide: /etc/hosts) ----------
sed -i "/[[:space:]]$DOCKER_HOST_NAME\$/d" /etc/hosts
echo "$DOCKER_HOST_IP $DOCKER_HOST_NAME" >> /etc/hosts
log "/etc/hosts: $DOCKER_HOST_IP $DOCKER_HOST_NAME"

# ---------- 6. Trust docker-node1's SSH host key ----------
# The firewall rule for this server may be created a few seconds after boot, so retry.
KNOWN_HOSTS="$DEPLOY_HOME/.ssh/known_hosts"
SCAN_FILE="$(mktemp)"
HOST_KEY_STATUS="not-trusted"
for attempt in $(seq 1 30); do
  # Scan into a file first (a "| grep -q" pipe can fail under "pipefail")
  ssh-keyscan -T 5 -t ed25519 "$DOCKER_HOST_IP" "$DOCKER_HOST_NAME" > "$SCAN_FILE" 2> /dev/null || true
  if grep -q ssh-ed25519 "$SCAN_FILE"; then
    cp "$SCAN_FILE" "$KNOWN_HOSTS"
    HOST_KEY_STATUS="trusted"
    break
  fi
  log "Waiting for SSH on $DOCKER_HOST_NAME (attempt $attempt/30)"
  sleep 5
done
rm -f "$SCAN_FILE"
touch "$KNOWN_HOSTS"
chown "$DEPLOY_USER:$DEPLOY_USER" "$KNOWN_HOSTS"
chmod 644 "$KNOWN_HOSTS"
log "docker-node1 host key: $HOST_KEY_STATUS"

# ---------- 7. Ansible project: inventory and ansible.cfg (as in the project guide) ----------
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$PROJECT_DIR"
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$STAGING_DIR"

cat > "$PROJECT_DIR/inventory" <<EOF
# Servers Ansible manages (written at boot by Terraform's install script)
[docker]
$DOCKER_HOST_NAME ansible_host=$DOCKER_HOST_IP
EOF

cat > "$PROJECT_DIR/ansible.cfg" <<EOF
[defaults]
inventory          = $PROJECT_DIR/inventory
remote_user        = $DEPLOY_USER
private_key_file   = $KEY_FILE
host_key_checking  = True
interpreter_python = auto_silent
retry_files_enabled = False

[privilege_escalation]
become          = True
become_user     = root
become_method   = sudo
become_ask_pass = False
EOF

chown "$DEPLOY_USER:$DEPLOY_USER" "$PROJECT_DIR/inventory" "$PROJECT_DIR/ansible.cfg"
chmod 644 "$PROJECT_DIR/inventory" "$PROJECT_DIR/ansible.cfg"

# Use this ansible.cfg from any folder, not only from inside $PROJECT_DIR
echo "export ANSIBLE_CONFIG=$PROJECT_DIR/ansible.cfg" > /etc/profile.d/ansible.sh
chmod 644 /etc/profile.d/ansible.sh
log "Ansible project ready: $PROJECT_DIR (inventory, ansible.cfg), staging: $STAGING_DIR"

# ---------- 8. SSH hardening: keys only, no root login ----------
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

# ---------- 9. Connection test: ansible -> docker-node1 (does not stop the bootstrap) ----------
PING_STATUS="failed"
if as_deploy env ANSIBLE_CONFIG="$PROJECT_DIR/ansible.cfg" ansible docker -m ping; then
  PING_STATUS="ok"
fi
log "Ansible ping to $DOCKER_HOST_NAME: $PING_STATUS"

# ---------- 10. Done marker (used to verify the bootstrap) ----------
cat > "$MARKER" <<EOF
server=$(hostname)
finished=$(date '+%Y-%m-%d %H:%M:%S %Z')
ansible=$(echo "$ANSIBLE_VERSION_LINE" | sed 's/.*\[core \(.*\)\].*/\1/')
deploy_user=$DEPLOY_USER
private_key=$KEY_FILE
docker_host=$DOCKER_HOST_NAME ($DOCKER_HOST_IP)
docker_host_key=$HOST_KEY_STATUS
ansible_ping=$PING_STATUS
project_dir=$PROJECT_DIR
staging_dir=$STAGING_DIR
EOF

log "ansible bootstrap complete"
