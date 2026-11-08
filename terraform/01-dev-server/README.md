# Stack: `01-dev-server` (dev1)

The developer machine from the project guide. You write code here and push it to GitHub. It is not part of the running application.

**Depends on:** `00-shared` (VPC, subnet, login key). Apply `00-shared` first.

## What it creates

| Resource | Details |
|---|---|
| EC2 instance `dev1` | t2.micro, Amazon Linux 2023, 10 GB encrypted gp3, IMDSv2 |
| Security group `emp-dev1-sg` | Inbound: SSH (22) from your IP only. Outbound: all |

No Elastic IP: the public IP changes when dev1 is stopped and started. Run `terraform output` to see the current one.

## Installed on first boot (`scripts/install.sh`)

| Step | Result |
|---|---|
| Hostname, timezone | `dev1`, `Asia/Kolkata` |
| OS updates | `dnf -y update` |
| Git, Node.js 22, npm | From the Amazon Linux 2023 repository |
| Workspace | `/devpro1`, owned by `ec2-user` |
| Repository | Cloned into `/devpro1/Employee-management` |
| Git identity | Set if `git_user_name` / `git_user_email` are given |
| Done marker | `/var/log/bootstrap-complete` |

The script runs once (cloud-init). Changing it makes Terraform replace dev1 with a fresh server.

## How it finds the shared resources

| Resource | Lookup |
|---|---|
| VPC | tags `Name=emp-vpc`, `Project=emp` |
| Subnet | tags `Tier=public`, `Project=emp` |
| Key pair | name `emp-login-key` |
| Your IP | https://checkip.amazonaws.com at plan time, unless `admin_cidr` is set |

## Usage

```bash
cd terraform/01-dev-server
cp terraform.tfvars.example terraform.tfvars   # optional
terraform init
terraform plan
terraform apply
```

## Checks

```bash
# Log in (command from: terraform output ssh_command)
ssh -i ~/.ssh/emp-project.pem ec2-user@<public_ip>

# On dev1: wait for the install script, then show the result
cloud-init status --wait
cat /var/log/bootstrap-complete
git --version && node -v && npm -v && hostname && ls /devpro1
```

The install takes about 2 to 4 minutes after the server starts.

## Your IP changed?

Your SSH rule is your IP at the time of `terraform apply`. If your IP changes (mobile network), run `terraform apply` again: only the firewall rule is updated, dev1 itself is not rebuilt.

## Troubleshooting

| Problem | Fix |
|---|---|
| `no matching EC2 VPC found` | Apply `00-shared` first |
| `ssh: connect ... timed out` | Your IP changed; run `terraform apply` again |
| `Permission denied (publickey)` | Use `-i ~/.ssh/emp-project.pem` and user `ec2-user` |
| `node: command not found` right after boot | The install is still running: `cloud-init status --wait` |
| Install failed | `sudo cat /var/log/bootstrap.log` (or `/var/log/cloud-init-output.log`) |

## Destroy

```bash
terraform destroy
```
