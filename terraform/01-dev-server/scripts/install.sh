#!/bin/bash
# =============================================================================
# dev1 bootstrap script
# Runs ONCE on the first boot, as root, through cloud-init (EC2 user_data).
# Terraform's templatefile() fills in the template values (hostname, timezone,
# node_major, repo_url, git_user_name, git_user_email) before the server starts.
#
# Installs: hostname, timezone, Git, Node.js + npm, project workspace /devpro1
# Logs:     /var/log/bootstrap.log (also /var/log/cloud-init-output.log)
# Done:     /var/log/bootstrap-complete
# =============================================================================

set -euo pipefail

LOG=/var/log/bootstrap.log
MARKER=/var/log/bootstrap-complete
WORKSPACE=/devpro1
DEV_USER=ec2-user

# Send all output to the log file and to the console log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Safe to run again: stop if setup already finished
if [ -f "$MARKER" ]; then
  log "Already bootstrapped, nothing to do"
  exit 0
fi

log "Starting dev1 bootstrap"

# ---------- 1. Identity: hostname and timezone (as in the project guide) ----------
hostnamectl set-hostname "${hostname}"
timedatectl set-timezone "${timezone}"
log "Hostname: $(hostname), timezone: ${timezone}"

# ---------- 2. Operating system updates ----------
dnf -y update
log "System packages updated"

# ---------- 3. Developer tools: Git and Node.js ----------
dnf -y install git "nodejs${node_major}" "nodejs${node_major}-npm"

# Make "node" and "npm" point to the installed version
alternatives --set node "/usr/bin/node-${node_major}"
log "Installed $(git --version), Node.js $(node -v), npm $(npm -v)"

# ---------- 4. Project workspace (as in the project guide: /devpro1) ----------
mkdir -p "$WORKSPACE"
chown "$DEV_USER:$DEV_USER" "$WORKSPACE"

# Run a command as the developer user, with the correct home folder
as_dev() { sudo -H -u "$DEV_USER" "$@"; }

if [ -n "${git_user_name}" ]; then
  as_dev git config --global user.name "${git_user_name}"
fi
if [ -n "${git_user_email}" ]; then
  as_dev git config --global user.email "${git_user_email}"
fi
as_dev git config --global init.defaultBranch main

if [ -n "${repo_url}" ]; then
  REPO_DIR="$WORKSPACE/$(basename "${repo_url}" .git)"
  if [ ! -d "$REPO_DIR/.git" ]; then
    as_dev git clone "${repo_url}" "$REPO_DIR"
    log "Cloned ${repo_url} into $REPO_DIR"
  fi
fi

# ---------- 5. Done marker (used to verify the bootstrap) ----------
cat > "$MARKER" <<EOF
server=$(hostname)
finished=$(date '+%Y-%m-%d %H:%M:%S %Z')
git=$(git --version | awk '{print $3}')
node=$(node -v)
npm=$(npm -v)
EOF

log "dev1 bootstrap complete"
