#!/usr/bin/env bash
# =============================================================================
# manage.sh
# One command to create, start, stop, check, destroy or recreate the whole
# AWS environment of the Employee Management System.
#
# Usage:
#   ./terraform/manage.sh <command> [-y]
#
# Commands:
#   up        Create or update everything (00 -> 04), wait until every server
#             finished its install script, print URLs and IPs
#   start     Start all stopped project servers, then check them
#   stop      Stop all project servers (no compute cost; disks and IPs are kept)
#   status    Show each stack and each server (read-only)
#   plan      Show what would change in each stack (read-only)
#   outputs   Show URLs, IPs and SSH commands (read-only)
#   destroy   Delete everything (04 -> 00), after typing the project name
#   recreate  destroy + up: a completely fresh environment
#   help      Show this help
#
# Options:
#   -y, --yes   Do not ask "continue?" (destroy still asks for the project name)
#
# Safety:
#   - Terraform only changes resources recorded in this project's state files.
#   - start/stop only select servers tagged Project=emp and ManagedBy=terraform
#     in the project region. Nothing else in the AWS account is touched.
# =============================================================================

set -euo pipefail

# ----------------------------- Settings --------------------------------------
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="emp"
REGION="ap-south-1"
STACKS="00-shared 01-dev-server 02-docker-server 03-ansible-server 04-jenkins-server"
STACKS_REVERSE="04-jenkins-server 03-ansible-server 02-docker-server 01-dev-server 00-shared"

LOGIN_KEY="$HOME/.ssh/${PROJECT}-project.pem"
KNOWN_HOSTS="$HOME/.ssh/${PROJECT}-known-hosts"   # separate file: servers are rebuilt often
BOOTSTRAP_TIMEOUT=900                              # seconds per server (Jenkins needs the longest)
ASSUME_YES=false

# All AWS CLI calls go to the project region
export AWS_REGION="$REGION"
export AWS_PAGER=""

# Download each Terraform provider once and reuse it in every stack folder
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"   # must exist before Terraform runs

# ----------------------------- Output helpers --------------------------------
if [ -t 1 ]; then
  BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  BLUE=""; GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi

step() { printf '\n%s==> %s%s\n' "${BLUE}${BOLD}" "$*" "${RESET}"; }
ok()   { printf '%s  ✔ %s%s\n' "${GREEN}" "$*" "${RESET}"; }
warn() { printf '%s  ! %s%s\n' "${YELLOW}" "$*" "${RESET}"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '%s  ✘ %s%s\n' "${RED}" "$*" "${RESET}" >&2; exit 1; }

confirm() {
  [ "$ASSUME_YES" = true ] && return 0
  printf '%s  ? %s [y/N] %s' "${YELLOW}" "$1" "${RESET}"
  local answer
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) fail "Cancelled, nothing was changed." ;; esac
}

# ----------------------------- Stack helpers ---------------------------------
# Server name created by each stack (empty for 00-shared)
server_of() {
  case "$1" in
    01-dev-server)     echo "dev1" ;;
    02-docker-server)  echo "docker-node1" ;;
    03-ansible-server) echo "ansible" ;;
    04-jenkins-server) echo "jenkins" ;;
    *)                 echo "" ;;
  esac
}

tf() { terraform -chdir="$TF_DIR/$1" "${@:2}"; }

tf_init() {
  tf "$1" init -input=false -no-color > "$TF_DIR/$1/.manage-init.log" 2>&1 \
    || { tail -20 "$TF_DIR/$1/.manage-init.log"; fail "terraform init failed in $1"; }
  rm -f "$TF_DIR/$1/.manage-init.log"
}

# Number of real resources in a stack's state (data lookups not counted; 0 = not created)
resource_count() {
  [ -s "$TF_DIR/$1/terraform.tfstate" ] || { echo 0; return; }
  [ -d "$TF_DIR/$1/.terraform" ] || tf_init "$1"
  local list
  list="$(tf "$1" state list 2>/dev/null || true)"
  printf '%s\n' "$list" | grep -c -v -E '(^|\.)data\.|^$' || true
}

output_of() { tf "$1" output -raw "$2" 2>/dev/null || true; }

# ----------------------------- AWS helpers -----------------------------------
# Project servers in a given state: prints "name instance-id" lines
servers_in_state() {
  aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT" "Name=tag:ManagedBy,Values=terraform" \
              "Name=instance-state-name,Values=$1" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId]' \
    --output text
}

# Does the server's firewall (as it is in AWS now) allow SSH from this Mac's current IP?
ssh_allowed_from_here() {
  local stack="$1" sg my_ip found
  sg="$(output_of "$stack" security_group_id)"
  my_ip="$(curl -fsS -m 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  [ -n "$sg" ] && [ -n "$my_ip" ] || return 0   # cannot check: do not block
  found="$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$sg" \
    --query "SecurityGroupRules[?IsEgress==\`false\` && FromPort==\`22\` && CidrIpv4=='$my_ip/32'] | length(@)" \
    --output text 2>/dev/null || echo 1)"
  [ "$found" != "0" ]
}

# ----------------------------- Checks ----------------------------------------
check_requirements() {
  step "Checking requirements"
  command -v terraform > /dev/null 2>&1 || fail "Terraform is not installed."
  command -v aws > /dev/null 2>&1       || fail "AWS CLI is not installed."
  command -v ssh > /dev/null 2>&1       || fail "ssh is not installed."
  ok "$(terraform version | sed -n 1p), $(aws --version 2>&1 | cut -d' ' -f1)"

  local account
  account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
    || fail "AWS CLI is not logged in. Check: aws sts get-caller-identity"
  ok "AWS account $account, region $REGION"

  local stack
  for stack in $STACKS; do
    [ -d "$TF_DIR/$stack" ] || fail "Missing stack folder: terraform/$stack"
  done
  ok "All 5 stack folders found"
}

# ----------------------------- Bootstrap check (SSH) -------------------------
# Wait until a server's install script finished, and check its marker file.
#   $1 = stack, $2 = text that must appear in the marker (optional)
wait_for_bootstrap() {
  local stack="$1" must_contain="${2:-}" server ip marker elapsed=0
  server="$(server_of "$stack")"
  ip="$(output_of "$stack" public_ip)"
  [ -n "$ip" ] || fail "No public IP for $server (terraform output in $stack)"
  [ -f "$LOGIN_KEY" ] || fail "Login key not found: $LOGIN_KEY (apply 00-shared first)"

  # Mobile IPs change: fail fast instead of waiting for an SSH timeout
  if ! ssh_allowed_from_here "$stack"; then
    fail "Your IP changed, so $server's firewall does not allow SSH from here. Run: $0 up (only the firewall rules are updated)"
  fi

  printf '  … waiting for %s (%s) to finish its install script (max %s min)\n' "$server" "$ip" "$((BOOTSTRAP_TIMEOUT / 60))"

  # A rebuilt server has a new SSH host key on the same IP: forget the old one
  touch "$KNOWN_HOSTS"
  ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" > /dev/null 2>&1 || true

  while [ "$elapsed" -lt "$BOOTSTRAP_TIMEOUT" ]; do
    marker="$(ssh -i "$LOGIN_KEY" \
      -o BatchMode=yes -o ConnectTimeout=8 \
      -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
      "ec2-user@$ip" 'sudo cloud-init status --wait > /dev/null 2>&1; cat /var/log/bootstrap-complete 2> /dev/null' 2> /dev/null || true)"

    if [ -n "$marker" ]; then
      case "$marker" in
        *"$must_contain"*) ;;
        *)
          printf '%s\n' "$marker" | sed 's/^/    /'
          fail "$server finished, but '$must_contain' is missing. Check: ssh -i $LOGIN_KEY ec2-user@$ip 'sudo tail -40 /var/log/bootstrap.log'"
          ;;
      esac
      ok "$server is ready"
      printf '%s\n' "$marker" | sed 's/^/    /'
      return 0
    fi

    sleep 15
    elapsed=$((elapsed + 15))
  done

  fail "$server did not finish in time. Check: ssh -i $LOGIN_KEY ec2-user@$ip 'sudo tail -40 /var/log/bootstrap.log'"
}

check_server() {
  case "$1" in
    01-dev-server)     wait_for_bootstrap "$1" "node=v" ;;
    02-docker-server)  wait_for_bootstrap "$1" "docker_service=active" ;;
    03-ansible-server) wait_for_bootstrap "$1" "ansible_ping=ok" ;;
    04-jenkins-server) wait_for_bootstrap "$1" "jenkins_web_ui=ready" ;;
  esac
}

# ----------------------------- Apply one stack -------------------------------
apply_stack() {
  local stack="$1" code=0
  local plan_file="$TF_DIR/$stack/.manage.tfplan" log="$TF_DIR/$stack/.manage.log"
  step "Stack $stack"
  tf_init "$stack"

  tf "$stack" plan -input=false -no-color -detailed-exitcode -out="$plan_file" > "$log" 2>&1 || code=$?
  case "$code" in
    0)
      ok "No changes"
      ;;
    2)
      if grep -q -E '^Plan:' "$log"; then
        info "$(grep -E '^Plan:' "$log" | sed -n 1p)"
      else
        info "Only output values change (no resources)"
      fi
      if ! tf "$stack" apply -input=false -no-color "$plan_file" > "$log" 2>&1; then
        tail -30 "$log"
        rm -f "$plan_file" "$log"
        fail "terraform apply failed in $stack (output above)"
      fi
      info "$(grep -E 'Apply complete' "$log" | sed -n 1p)"
      ok "Applied"
      ;;
    *)
      tail -30 "$log"
      rm -f "$plan_file" "$log"
      fail "terraform plan failed in $stack (output above)"
      ;;
  esac
  rm -f "$plan_file" "$log"
}

# ----------------------------- Start / stop servers --------------------------
# Start order matters: docker-node1 -> ansible -> jenkins -> dev1
start_servers() {
  local stopped name id ids=""
  stopped="$(servers_in_state stopped)"
  [ -n "$stopped" ] || { ok "No stopped project servers"; return 0; }

  for name in docker-node1 ansible jenkins dev1; do
    id="$(printf '%s\n' "$stopped" | awk -v n="$name" '$1 == n {print $2}')"
    if [ -n "$id" ]; then
      aws ec2 start-instances --instance-ids "$id" > /dev/null
      ok "Starting $name ($id)"
      ids="$ids $id"
    fi
  done

  # shellcheck disable=SC2086
  aws ec2 wait instance-running --instance-ids $ids
  ok "All project servers are running"

  # Public IPs of servers without an Elastic IP change on start: refresh the outputs
  local stack
  for stack in $STACKS; do
    if [ "$(resource_count "$stack")" -gt 0 ]; then
      tf "$stack" apply -refresh-only -auto-approve -input=false -no-color > /dev/null 2>&1 || warn "Could not refresh outputs of $stack"
    fi
  done
  ok "Terraform outputs refreshed (new public IPs)"
}

stop_servers() {
  local running name id ids=""
  running="$(servers_in_state "pending,running")"
  [ -n "$running" ] || { ok "No running project servers"; return 0; }

  for name in dev1 jenkins ansible docker-node1; do
    id="$(printf '%s\n' "$running" | awk -v n="$name" '$1 == n {print $2}')"
    if [ -n "$id" ]; then
      aws ec2 stop-instances --instance-ids "$id" > /dev/null
      ok "Stopping $name ($id)"
      ids="$ids $id"
    fi
  done

  # shellcheck disable=SC2086
  aws ec2 wait instance-stopped --instance-ids $ids
  ok "All project servers are stopped"
}

# ----------------------------- Summary ---------------------------------------
print_summary() {
  local docker_ip jenkins_url
  docker_ip="$(output_of 02-docker-server public_ip)"
  jenkins_url="$(output_of 04-jenkins-server jenkins_url)"

  step "Environment"
  if [ -n "$docker_ip" ]; then
    info "App (after deployment): http://$docker_ip"
  fi
  if [ -n "$jenkins_url" ]; then
    info "Jenkins:                $jenkins_url"
    info "GitHub webhook URL:     $(output_of 04-jenkins-server github_webhook_url)"
  fi
  info ""
  local stack server
  for stack in 01-dev-server 02-docker-server 03-ansible-server 04-jenkins-server; do
    server="$(server_of "$stack")"
    if [ "$(resource_count "$stack")" -gt 0 ]; then
      printf '    %-13s %s\n' "$server" "$(output_of "$stack" ssh_command)"
    fi
  done

  if [ -n "$docker_ip" ]; then
    printf '\n%s  MongoDB Atlas: make sure %s is in Security > Network Access%s\n' "${YELLOW}" "$docker_ip" "${RESET}"
  fi
}

# ----------------------------- Commands --------------------------------------
cmd_up() {
  check_requirements
  printf '\n  This creates or updates all project resources in %s (00 -> 04).\n' "$REGION"
  confirm "Continue?"

  # Stacks 03 and 04 look up running servers, so start any stopped ones first
  step "Making sure existing servers are running"
  start_servers

  local stack
  for stack in $STACKS; do
    apply_stack "$stack"
    if [ -n "$(server_of "$stack")" ]; then
      check_server "$stack"
    fi
  done

  print_summary
  printf '\n%s  Environment is up.%s\n\n' "${GREEN}${BOLD}" "${RESET}"
}

cmd_start() {
  check_requirements
  step "Starting project servers"
  start_servers

  local stack
  for stack in 02-docker-server 03-ansible-server 04-jenkins-server 01-dev-server; do
    if [ "$(resource_count "$stack")" -gt 0 ]; then
      check_server "$stack"
    fi
  done
  print_summary
}

cmd_stop() {
  check_requirements
  printf '\n  This stops all project servers. Disks and Elastic IPs are kept\n'
  printf '  (small storage and IP cost). Start again with: %s start\n' "$0"
  confirm "Continue?"
  step "Stopping project servers"
  stop_servers
}

cmd_status() {
  check_requirements

  step "Stacks"
  local stack count
  for stack in $STACKS; do
    count="$(resource_count "$stack")"
    if [ "$count" -gt 0 ]; then ok "$(printf '%-20s created (%s resources)' "$stack" "$count")"
    else warn "$(printf '%-20s not created' "$stack")"; fi
  done

  step "Servers"
  local table
  table="$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT" "Name=tag:ManagedBy,Values=terraform" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,InstanceType,PrivateIpAddress,PublicIpAddress]' \
    --output text)"
  if [ -n "$table" ]; then
    printf '    %-14s %-9s %-10s %-13s %s\n' NAME STATE TYPE PRIVATE_IP PUBLIC_IP
    printf '%s\n' "$table" | sort | awk '{printf "    %-14s %-9s %-10s %-13s %s\n", $1, $2, $3, $4, ($5 == "None" ? "-" : $5)}'
  else
    warn "No project servers exist"
  fi
}

cmd_plan() {
  check_requirements
  step "Planned changes (read-only)"
  local stack code
  for stack in $STACKS; do
    tf_init "$stack"
    code=0
    tf "$stack" plan -input=false -no-color -lock=false -detailed-exitcode > "$TF_DIR/$stack/.manage-plan.log" 2>&1 || code=$?
    case "$code" in
      0) ok "$(printf '%-20s no changes' "$stack")" ;;
      2)
        if grep -q -E '^Plan:' "$TF_DIR/$stack/.manage-plan.log"; then
          warn "$(printf '%-20s %s' "$stack" "$(grep -E '^Plan:' "$TF_DIR/$stack/.manage-plan.log" | sed -n 1p)")"
        else
          warn "$(printf '%-20s only output values change (no resources)' "$stack")"
        fi
        ;;
      *) warn "$(printf '%-20s plan failed: %s' "$stack" "$(grep -m1 'Error:' "$TF_DIR/$stack/.manage-plan.log")")" ;;
    esac
    rm -f "$TF_DIR/$stack/.manage-plan.log"
  done
}

cmd_outputs() {
  check_requirements
  print_summary
}

cmd_destroy() {
  check_requirements
  printf '\n%s  This DELETES every resource of this project (04 -> 00):%s\n' "${RED}${BOLD}" "${RESET}"
  printf '  4 servers, their disks, Elastic IPs, firewalls, IAM role, VPC, keys.\n'
  printf '  Nothing outside this project is touched. This cannot be undone.\n'
  printf '\n  Type the project name (%s) to confirm: ' "$PROJECT"
  local answer
  read -r answer
  [ "$answer" = "$PROJECT" ] || fail "Cancelled, nothing was deleted."

  # Stacks 03 and 04 look up running servers, so start any stopped ones first
  step "Making sure existing servers are running"
  start_servers

  local stack
  for stack in $STACKS_REVERSE; do
    step "Destroying $stack"
    if [ "$(resource_count "$stack")" -eq 0 ]; then
      ok "Nothing to destroy"
      continue
    fi
    tf_init "$stack"
    local log="$TF_DIR/$stack/.manage.log"
    if ! tf "$stack" destroy -auto-approve -input=false -no-color > "$log" 2>&1; then
      tail -30 "$log"
      rm -f "$log"
      fail "terraform destroy failed in $stack (output above). Fix it, then run: $0 destroy"
    fi
    info "$(grep -E 'Destroy complete' "$log" | sed -n 1p)"
    rm -f "$log"
    if [ "$(resource_count "$stack")" -ne 0 ]; then
      fail "Some resources in $stack were not destroyed. Run: terraform -chdir=terraform/$stack destroy"
    fi
    ok "Destroyed"
  done

  printf '\n%s  Everything is destroyed. No project resources remain.%s\n' "${GREEN}${BOLD}" "${RESET}"
  printf '  Next time, after "%s up", add the NEW docker-node1 IP in MongoDB Atlas.\n\n' "$0"
}

cmd_recreate() {
  cmd_destroy
  ASSUME_YES=true
  cmd_up
}

cmd_help() {
  # Print the header comment block (without the leading "# ")
  sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

# ----------------------------- Entry point -----------------------------------
main() {
  local command="${1:-help}"
  [ $# -gt 0 ] && shift
  local arg
  for arg in "$@"; do
    case "$arg" in
      -y|--yes) ASSUME_YES=true ;;
      *) fail "Unknown option: $arg" ;;
    esac
  done

  case "$command" in
    up)       cmd_up ;;
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    status)   cmd_status ;;
    plan)     cmd_plan ;;
    outputs)  cmd_outputs ;;
    destroy)  cmd_destroy ;;
    recreate) cmd_recreate ;;
    help|-h|--help) cmd_help ;;
    *) printf 'Unknown command: %s\n\n' "$command" >&2; cmd_help; exit 1 ;;
  esac
}

main "$@"
