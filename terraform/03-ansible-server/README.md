# Stack: `03-ansible-server` (ansible)

The Ansible control node. Jenkins uploads the app package here, and Ansible deploys it to docker-node1.

**Depends on:** `00-shared` (VPC, subnet, keys) and `02-docker-server` (docker-node1 must be **running**).

## What it creates

| Resource | Details |
|---|---|
| EC2 instance `ansible` | t2.micro, Amazon Linux 2023, 10 GB encrypted gp3, IMDSv2 |
| Security group `emp-ansible-sg` | Inbound: SSH (22) from your IP. Outbound: all |
| IAM role `emp-ansible-role` + instance profile `emp-ansible-profile` | May read **only** `/emp/ssh/internal-private-key` (and decrypt it only through SSM) |
| Rule on **docker-node1's** firewall | SSH (22) from the ansible server's firewall only |

SSH from Jenkins to this server is added later by `04-jenkins-server`.

## Installed on first boot (`scripts/install.sh`)

| Step | Result |
|---|---|
| Hostname, timezone | `ansible`, `Asia/Kolkata` |
| OS updates, Ansible | `dnf -y update`, `ansible-core` (checked with `ansible-playbook --version`) |
| Deploy user `itadmin` | No password (locked), passwordless sudo, accepts the internal key (for Jenkins) |
| Internal private key | Read from SSM with the IAM role, saved as `/home/itadmin/.ssh/id_rsa` (600) |
| `/etc/hosts` | `docker-node1` -> its private IP |
| Host key | docker-node1's SSH host key added to `known_hosts` (host key checking stays on) |
| `/opt/project` | `inventory` (docker-node1) and `ansible.cfg` (user, key, become) |
| `/opt/docker` | Staging folder for Jenkins uploads |
| SSH hardening | Password login and root login disabled |
| Connection test | `ansible docker -m ping`, result saved in the marker |
| Done marker | `/var/log/bootstrap-complete` |

## Design notes

- **No secret in code, user_data or this folder's state.** Terraform only checks that the key parameter exists (`with_decryption = false`); the server downloads it at boot through its IAM role.
- **Always the correct inventory.** docker-node1's private IP is part of the install script. If docker-node1 is rebuilt with a new IP, this server is rebuilt too.
- **Least privilege.** Only this server may SSH into docker-node1, and this server may read only one secret.

## Usage

```bash
cd terraform/03-ansible-server
terraform init
terraform plan
terraform apply
```

## Checks

```bash
ssh -i ~/.ssh/emp-project.pem ec2-user@<public_ip>

# On the ansible server
sudo cloud-init status --wait
cat /var/log/bootstrap-complete          # ansible_ping=ok expected
sudo su - itadmin
ansible docker -m ping                   # docker-node1 | SUCCESS => "ping": "pong"
ansible docker -a "docker --version"     # runs a command on docker-node1
cat /opt/project/inventory /opt/project/ansible.cfg
exit
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `Your query returned no results` (aws_instance) | docker-node1 is not running; apply or start `02-docker-server` first |
| Marker shows `ansible_ping=failed` | Run `ansible docker -m ping -vvv` as itadmin; check the docker-node1 firewall rule exists |
| `Host key verification failed` | docker-node1 was replaced without rebuilding this server: `ssh-keyscan docker-node1 >> ~/.ssh/known_hosts` as itadmin, or run `terraform apply` here |
| `could not read a valid private key from SSM` | Check `00-shared` was applied and the role policy: `sudo cat /var/log/bootstrap.log` |
| `ssh: connect ... timed out` from your Mac | Your IP changed; run `terraform apply` again |

## Destroy

Destroy `04-jenkins-server` first (it adds a rule to this server's firewall), then:

```bash
terraform destroy
```

This also removes the SSH rule from docker-node1's firewall.
