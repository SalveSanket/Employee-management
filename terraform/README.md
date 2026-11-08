# Infrastructure (Terraform)

All AWS resources of the Employee Management System, in region `ap-south-1` (Mumbai).
Every server is a separate stack with its own state, built from one shared module.

## Stacks

| Order | Folder | Creates | Depends on |
|---|---|---|---|
| 1 | [`00-shared`](00-shared) | VPC, public subnet, internet gateway, login key, internal SSH key (SSM) | - |
| 2 | [`01-dev-server`](01-dev-server) | `dev1`: Git, Node.js, project workspace | 00 |
| 3 | [`02-docker-server`](02-docker-server) | `docker-node1`: Docker, deploy user, Elastic IP | 00 |
| 4 | [`03-ansible-server`](03-ansible-server) | `ansible`: Ansible, inventory, IAM role (reads the internal key) | 00, 02 |
| 5 | [`04-jenkins-server`](04-jenkins-server) | `jenkins`: Jenkins LTS, Java 21, Node.js, Elastic IP | 00, 03 |
| - | [`modules/ec2-server`](modules/ec2-server) | Reusable server template used by stacks 01 to 04 | - |

Create in order 00 -> 04, destroy in reverse 04 -> 00.

```
GitHub ──webhook──> jenkins ──SSH──> ansible ──SSH──> docker-node1 (app on :80) ──> MongoDB Atlas
                      ^                                     ^
                      └──────── dev1 pushes to GitHub ──────┘ (users open the app)
```

## `manage.sh`: the whole environment with one command

Run from the project root:

| Command | What it does |
|---|---|
| `./terraform/manage.sh up` | Create or update all stacks (00 -> 04), wait until every server finished its install script, print URLs and IPs |
| `./terraform/manage.sh status` | Stacks (created or not) and servers (state, IPs). Read-only |
| `./terraform/manage.sh plan` | What would change in each stack. Read-only |
| `./terraform/manage.sh outputs` | URLs, IPs and SSH commands. Read-only |
| `./terraform/manage.sh stop` | Stop all project servers (no compute cost; disks and Elastic IPs are kept) |
| `./terraform/manage.sh start` | Start stopped servers (docker -> ansible -> jenkins -> dev1), then check them |
| `./terraform/manage.sh destroy` | Delete everything (04 -> 00) after typing the project name |
| `./terraform/manage.sh recreate` | `destroy` + `up`: a completely fresh environment |

Add `-y` to skip the "Continue?" question (`destroy` always asks for the project name).

### Safety

- Terraform only changes resources recorded in this project's state files.
- `start` and `stop` only select servers tagged `Project=emp` and `ManagedBy=terraform` in `ap-south-1`.
- Every command stops at the first error and shows the Terraform output.
- Before waiting for a server, the script checks that its firewall allows SSH from your **current** IP. If your IP changed, it tells you to run `up` (only the firewall rules are updated).

### After `up` following a `destroy`

docker-node1 gets a **new** Elastic IP. Add it in MongoDB Atlas (Security > Network Access); the script prints it at the end.

## Requirements

- Terraform >= 1.5, AWS CLI v2 logged in (`aws sts get-caller-identity`)
- Providers are downloaded once into `~/.terraform.d/plugin-cache` and reused by every stack.

## Never committed

`terraform.tfstate*`, `terraform.tfvars`, `.terraform/`, `*.pem`: they contain secrets or machine-specific data and are ignored by Git.
