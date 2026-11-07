# Module: `ec2-server`

Reusable template for one EC2 server. All four servers (dev1, docker-node1, ansible, jenkins) are built from this module.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_security_group` | The server's own firewall |
| `aws_vpc_security_group_ingress_rule` | One resource per inbound rule (from `ingress_rules`) |
| `aws_vpc_security_group_egress_rule` | All outbound traffic allowed |
| `aws_instance` | The server: Amazon Linux 2023, encrypted gp3 disk, IMDSv2 only |
| `aws_eip` (optional) | Fixed public IP when `associate_elastic_ip = true` |

## Built-in standards

- **Bootstrapping:** `user_data` (the folder's `install.sh`) runs once on first boot through cloud-init.
- **Immutable servers:** changing `user_data` rebuilds the server (`user_data_replace_on_change`).
- **Security:** IMDSv2 required, encrypted disk, firewall per server, rules only as given.
- **Cost:** `standard` CPU credits on t-type instances (no burst charges).
- **Stability:** a new Amazon Linux release does not rebuild a running server (`ignore_changes = [ami]`).
- **Discovery:** every resource is tagged `Project`, `Role`, `ManagedBy`, so other folders can find it.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project` | string | `"emp"` | Prefix for names, Project tag |
| `name` | string | required | Server name, e.g. `docker-node1` |
| `role` | string | required | `dev`, `jenkins`, `ansible` or `docker` |
| `tags` | map(string) | `{}` | Extra tags |
| `instance_type` | string | `"t2.micro"` | EC2 size |
| `ami_id` | string | `null` | AMI; null = latest Amazon Linux 2023 |
| `root_volume_size` | number | `10` | Disk size in GB (min 8) |
| `user_data` | string | `""` | Bootstrap script |
| `iam_instance_profile` | string | `null` | Instance profile for AWS permissions |
| `associate_elastic_ip` | bool | `false` | Attach a fixed public IP |
| `vpc_id` | string | required | VPC ID |
| `subnet_id` | string | required | Subnet ID |
| `key_name` | string | required | SSH key pair name |
| `ingress_rules` | map(object) | `{}` | Inbound rules, each with `description`, `port`, optional `protocol` (default tcp), and exactly one of `cidr` or `source_security_group_id` |

## Outputs

| Name | Description |
|---|---|
| `instance_id` | EC2 instance ID |
| `name` | Server name |
| `public_ip` | Elastic IP if attached, else the normal public IP |
| `private_ip` | Private IP inside the VPC |
| `security_group_id` | Security group ID |
| `ami_id` | AMI used |

## Example

```hcl
module "server" {
  source = "../modules/ec2-server"

  name          = "docker-node1"
  role          = "docker"
  instance_type = "t2.micro"

  vpc_id    = data.aws_vpc.main.id
  subnet_id = data.aws_subnet.public.id
  key_name  = "emp-login-key"

  user_data            = templatefile("${path.module}/scripts/install.sh", { hostname = "docker-node1" })
  associate_elastic_ip = true

  ingress_rules = {
    ssh-admin = { description = "SSH from my IP", port = 22, cidr = "203.0.113.10/32" }
    http      = { description = "Website",        port = 80, cidr = "0.0.0.0/0" }
  }
}
```
