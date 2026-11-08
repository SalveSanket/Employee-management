#!/bin/bash
# =============================================================================
# jenkins server bootstrap script
# Runs ONCE on the first boot, as root, through cloud-init (EC2 user_data).
# Terraform's templatefile() fills in the template values (hostname, timezone,
# java_major, node_major, jenkins_port) before the server starts.
#
# Installs Jenkins and its dependencies ONLY. Jenkins itself (unlock, plugins,
# admin user, credentials, jobs) is set up manually in the web UI.
#
# Installs: hostname, timezone, fontconfig, Java (Amazon Corretto), Git,
#           Node.js + npm (pipeline build tools), Jenkins LTS (official repo),
#           Jenkins enabled on every boot, SSH hardening
# Logs:     /var/log/bootstrap.log (also /var/log/cloud-init-output.log)
# Done:     /var/log/bootstrap-complete
# =============================================================================

set -euo pipefail

LOG=/var/log/bootstrap.log
MARKER=/var/log/bootstrap-complete
JENKINS_PORT="${jenkins_port}"
JENKINS_REPO_URL="https://pkg.jenkins.io/rpm-stable/jenkins.repo"
JENKINS_KEY_URL="https://pkg.jenkins.io/rpm-stable/repodata/repomd.xml.key"
INITIAL_PASSWORD_FILE=/var/lib/jenkins/secrets/initialAdminPassword

# Send all output to the log file and to the console log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[bootstrap] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Safe to run again: stop if setup already finished
if [ -f "$MARKER" ]; then
  log "Already bootstrapped, nothing to do"
  exit 0
fi

log "Starting jenkins bootstrap"

# ---------- 1. Identity: hostname and timezone (as in the project guide) ----------
hostnamectl set-hostname "${hostname}"
timedatectl set-timezone "${timezone}"
log "Hostname: $(hostname), timezone: ${timezone}"

# ---------- 2. Operating system updates ----------
dnf -y update
log "System packages updated"

# ---------- 3. Jenkins dependencies: fontconfig and Java ----------
# Java must be installed BEFORE Jenkins, otherwise the service cannot find it
dnf -y install fontconfig "java-${java_major}-amazon-corretto-headless"
JAVA_VERSION_LINE="$(java -version 2>&1 | sed -n 1p)"
log "Installed Java: $JAVA_VERSION_LINE"

# ---------- 4. Pipeline build tools: Git and Node.js ----------
dnf -y install git "nodejs${node_major}" "nodejs${node_major}-npm"
alternatives --set node "/usr/bin/node-${node_major}"
log "Installed $(git --version), Node.js $(node -v), npm $(npm -v)"

# ---------- 5. Jenkins LTS from the official repository ----------
# The repository and every package are verified with the Jenkins signing key
curl -fsSL --retry 5 -o /etc/yum.repos.d/jenkins.repo "$JENKINS_REPO_URL"
rpm --import "$JENKINS_KEY_URL"
dnf -y install jenkins
log "Installed Jenkins $(rpm -q --queryformat '%%{VERSION}' jenkins)"

# ---------- 6. Start Jenkins now and on every boot ----------
systemctl daemon-reload
systemctl enable --now jenkins

# The first start takes 1 to 3 minutes: wait until the web UI answers
JENKINS_HTTP="not-ready"
for attempt in $(seq 1 60); do
  CODE="$(curl -s -o /dev/null -m 5 -w '%%{http_code}' "http://localhost:$JENKINS_PORT/login" || true)"
  if [ "$CODE" = "200" ]; then
    JENKINS_HTTP="ready"
    break
  fi
  log "Waiting for the Jenkins web UI (attempt $attempt/60, HTTP $CODE)"
  sleep 5
done

if [ "$JENKINS_HTTP" != "ready" ]; then
  log "ERROR: Jenkins did not answer on port $JENKINS_PORT. See: journalctl -u jenkins"
  exit 1
fi

# The setup wizard password must exist for the manual setup
for attempt in $(seq 1 12); do
  [ -s "$INITIAL_PASSWORD_FILE" ] && break
  sleep 5
done
[ -s "$INITIAL_PASSWORD_FILE" ] || { log "ERROR: $INITIAL_PASSWORD_FILE not found"; exit 1; }
log "Jenkins web UI ready on port $JENKINS_PORT; setup wizard password created"

# ---------- 7. SSH hardening: keys only, no root login ----------
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

# ---------- 8. Done marker (used to verify the bootstrap) ----------
cat > "$MARKER" <<EOF
server=$(hostname)
finished=$(date '+%Y-%m-%d %H:%M:%S %Z')
jenkins=$(rpm -q --queryformat '%%{VERSION}' jenkins)
jenkins_service=$(systemctl is-active jenkins)
jenkins_on_boot=$(systemctl is-enabled jenkins)
jenkins_web_ui=$JENKINS_HTTP (port $JENKINS_PORT)
java=$JAVA_VERSION_LINE
git=$(git --version | awk '{print $3}')
node=$(node -v)
npm=$(npm -v)
EOF

log "jenkins bootstrap complete"
