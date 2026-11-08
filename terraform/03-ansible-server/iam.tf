# =============================================================================
# 03-ansible-server: IAM role
# The ansible server may read exactly ONE secret: the internal SSH private key.
# Nothing else in the AWS account is accessible from this server.
# =============================================================================

data "aws_caller_identity" "current" {}

# The private key parameter created by 00-shared.
# with_decryption = false: Terraform only checks that it exists, it never reads the key,
# so the private key is not stored in this folder's state file.
data "aws_ssm_parameter" "internal_private_key" {
  name            = "/${var.project}/ssh/internal-private-key"
  with_decryption = false
}

# AWS managed key that encrypts SecureString parameters
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# Only EC2 servers may use this role
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    sid     = "Ec2AssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "read_private_key" {
  statement {
    sid       = "ReadInternalPrivateKeyOnly"
    actions   = ["ssm:GetParameter"]
    resources = [data.aws_ssm_parameter.internal_private_key.arn]
  }

  statement {
    sid       = "DecryptThroughSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ansible" {
  name               = "${var.project}-ansible-role"
  description        = "Ansible server: read the internal SSH key from SSM"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy" "read_private_key" {
  name   = "${var.project}-ansible-read-private-key"
  role   = aws_iam_role.ansible.id
  policy = data.aws_iam_policy_document.read_private_key.json
}

# Lets an EC2 server use the role
resource "aws_iam_instance_profile" "ansible" {
  name = "${var.project}-ansible-profile"
  role = aws_iam_role.ansible.name
}
