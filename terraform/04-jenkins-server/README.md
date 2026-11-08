# Stack: `04-jenkins-server` (jenkins)

The CI/CD server. This folder **installs Jenkins and its dependencies only**. Jenkins itself (unlock, plugins, admin user, credentials, pipeline job, webhook) is set up manually in the web UI.

**Depends on:** `00-shared` (VPC, subnet, login key) and `03-ansible-server` (ansible must be **running**).

## What it creates

| Resource | Details |
|---|---|
| EC2 instance `jenkins` | t3.small (2 GB), Amazon Linux 2023, 20 GB encrypted gp3, IMDSv2 |
| Elastic IP `emp-jenkins-eip` | Fixed Jenkins URL and GitHub webhook URL |
| Security group `emp-jenkins-sg` | Inbound: SSH (22) and Jenkins UI (8080) from your IP; 8080 from GitHub's official webhook IP ranges. Outbound: all |
| Rule on the **ansible server's** firewall | SSH (22) from the jenkins firewall only |

No IAM role: Jenkins has no AWS permissions.

## Installed on first boot (`scripts/install.sh`)

| Step | Result |
|---|---|
| Hostname, timezone | `jenkins`, `Asia/Kolkata` |
| OS updates | `dnf -y update` |
| Jenkins dependencies | `fontconfig`, Java 21 (`java-21-amazon-corretto-headless`), installed **before** Jenkins |
| Pipeline build tools | Git, Node.js 22 + npm |
| Jenkins LTS | Official repository `pkg.jenkins.io/rpm-stable`, packages and repository verified with the Jenkins signing key |
| Service | Started and enabled on every boot (`systemctl enable --now jenkins`) |
| Readiness | Waits until `http://localhost:8080/login` answers and the setup wizard password exists |
| SSH hardening | Password login and root login disabled |
| Done marker | `/var/log/bootstrap-complete` |

## GitHub webhook IP ranges

Terraform reads `https://api.github.com/meta` at plan time and allows only the IPv4 `hooks` ranges on port 8080. If GitHub changes its ranges, run `terraform apply` again. Disable with `allow_github_webhooks = false`.

## Usage

```bash
cd terraform/04-jenkins-server
terraform init
terraform plan
terraform apply
```

## Checks

```bash
ssh -i ~/.ssh/emp-project.pem ec2-user@<public_ip>

# On the jenkins server
sudo cloud-init status --wait
cat /var/log/bootstrap-complete
systemctl is-active jenkins && systemctl is-enabled jenkins
java -version && git --version && node -v && npm -v
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/login     # 200
sudo cat /var/lib/jenkins/secrets/initialAdminPassword                    # for the first login
```

Then open `terraform output jenkins_url` in the browser: the **Unlock Jenkins** page appears.

The install takes about 4 to 6 minutes after the server starts.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Your query returned no results` (aws_instance) | The ansible server is not running; apply `03-ansible-server` first |
| `Could not read GitHub webhook IP ranges` | Temporary GitHub API problem or rate limit; retry, or set `allow_github_webhooks = false` |
| Browser cannot open Jenkins | Your IP changed; run `terraform apply` again (only the rules are updated) |
| `jenkins_web_ui=not-ready` or install failed | `sudo cat /var/log/bootstrap.log` and `sudo journalctl -u jenkins --no-pager | tail -50` |

## Destroy

```bash
terraform destroy
```

This also removes the SSH rule from the ansible server's firewall.
