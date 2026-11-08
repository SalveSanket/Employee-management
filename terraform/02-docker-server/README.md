# Stack: `02-docker-server` (docker-node1)

The application server. Ansible deploys the two app containers here (`emp-client`: Nginx + React, `emp-server`: Node.js API).

**Depends on:** `00-shared` (VPC, subnet, login key, internal public key). Apply `00-shared` first.

## What it creates

| Resource | Details |
|---|---|
| EC2 instance `docker-node1` | t2.micro, Amazon Linux 2023, 15 GB encrypted gp3, IMDSv2 |
| Elastic IP `emp-docker-node1-eip` | Fixed public IP: app URL and MongoDB Atlas allowlist |
| Security group `emp-docker-node1-sg` | Inbound: SSH (22) from your IP, HTTP (80) from everyone. Outbound: all |

Port 5050 (backend) is **not** opened: the API is reached only through Nginx inside Docker.

The SSH rule *from the ansible server* is added later by `03-ansible-server`, because the ansible firewall does not exist yet when this server is built.

## Installed on first boot (`scripts/install.sh`)

| Step | Result |
|---|---|
| Hostname, timezone | `docker-node1`, `Asia/Kolkata` |
| OS updates | `dnf -y update` |
| Docker | Installed, running, enabled on every boot (`systemctl enable --now docker`) |
| Deploy user `itadmin` | No password (locked), member of `docker`, passwordless sudo, accepts only the internal SSH key |
| App folder | `/opt/docker`, owned by `itadmin` |
| SSH hardening | Password login and root login disabled |
| Done marker | `/var/log/bootstrap-complete` |

## Usage

```bash
cd terraform/02-docker-server
cp terraform.tfvars.example terraform.tfvars   # optional
terraform init
terraform plan
terraform apply
```

## Checks

```bash
# Log in (command from: terraform output ssh_command)
ssh -i ~/.ssh/emp-project.pem ec2-user@<public_ip>

# On docker-node1
sudo cloud-init status --wait
cat /var/log/bootstrap-complete
docker --version && systemctl is-active docker && systemctl is-enabled docker
id itadmin
sudo ls -l /home/itadmin/.ssh/authorized_keys /opt/docker -d
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
```

Expected: `active`, `enabled`, `itadmin` in group `docker`, `passwordauthentication no`, `permitrootlogin no`.

## After apply: MongoDB Atlas

Add the Elastic IP (`terraform output public_ip`) in Atlas > Security > Network Access, so the backend container can reach the database.

## Troubleshooting

| Problem | Fix |
|---|---|
| `no matching EC2 VPC found` | Apply `00-shared` first |
| `ssh: connect ... timed out` | Your IP changed; run `terraform apply` again (only the rule is updated) |
| `docker: command not found` right after boot | The install is still running: `sudo cloud-init status --wait` |
| Install failed | `sudo cat /var/log/bootstrap.log` |

## Destroy

Destroy `03-ansible-server` first (it adds a rule to this server's firewall), then:

```bash
terraform destroy
```
