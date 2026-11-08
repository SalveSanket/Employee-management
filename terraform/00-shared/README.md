# Stack: `00-shared`

Foundation used by all four servers. Create it **first**, destroy it **last**.

## What it creates

| Resource | Name | Purpose |
|---|---|---|
| VPC | `emp-vpc` (10.0.0.0/16) | Private network |
| Default security group | `emp-default-sg-unused` | Locked down (no rules), never used |
| Internet gateway | `emp-igw` | Internet access |
| Public subnet | `emp-public-subnet` (10.0.1.0/24), tag `Tier=public` | Where the servers live |
| Route table + route | `emp-public-rt`, 0.0.0.0/0 -> IGW | Sends internet traffic out |
| EC2 key pair | `emp-login-key` (ED25519) | Your SSH login |
| Local file | `~/.ssh/emp-project.pem` (chmod 400) | Login private key on your Mac |
| SSM parameter (SecureString) | `/emp/ssh/internal-private-key` (RSA 4096) | Server-to-server private key, encrypted |
| SSM parameter (String) | `/emp/ssh/internal-public-key` | Server-to-server public key |

Cost: **$0**. None of these resources is charged.

## How other folders find these resources

| Resource | Lookup |
|---|---|
| VPC | tag `Name = emp-vpc` |
| Subnet | tag `Tier = public` + `Project = emp` |
| Key pair | name `emp-login-key` |
| Keys | SSM parameter names above |

## Usage

```bash
cd terraform/00-shared
terraform init
terraform plan
terraform apply
terraform output
```

## Checks

```bash
ls -l ~/.ssh/emp-project.pem
aws ec2 describe-vpcs --region ap-south-1 --filters Name=tag:Name,Values=emp-vpc --query 'Vpcs[].VpcId'
aws ssm get-parameter --region ap-south-1 --name /emp/ssh/internal-public-key --query Parameter.Value --output text
```

## Destroy (only after all server folders are destroyed)

```bash
terraform destroy
```

## Security notes

- The login key file and `terraform.tfstate` contain private keys. Both stay on your machine and are ignored by Git.
- The internal private key is stored as an encrypted SecureString. Only servers with an IAM role allowing `ssm:GetParameter` on it can read it.
