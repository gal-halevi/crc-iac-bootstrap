# Create an S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  acl = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# Block public access for the S3 bucket
resource "aws_s3_bucket_public_access_block" "tf_state_public_block" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create a DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# OIDC GitHub provider
resource "aws_iam_openid_connect_provider" "github_oidc_idp" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# Create the OIDC roles for CI/CD
module "oidc_role" {
  source                   = "./modules/iam_oidc_role"
  for_each                 = var.oidc_roles_and_subjects
  role_name                = "oidc_${each.key}_role"
  oidc_provider_arn        = aws_iam_openid_connect_provider.github_oidc_idp.arn
  oidc_subject_policy_list = each.value
}

# All required permissions for backend/frontend tf remote state
data "aws_iam_policy_document" "tf_remote_state" {
  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.terraform_state.arn]
  }
  statement {
    sid    = "S3BucketObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  statement {
    sid    = "DynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [aws_dynamodb_table.terraform_locks.arn]
  }
}

# Create policy for tf remote state
resource "aws_iam_policy" "tf_remote_state_policy" {
  name        = "tf-remote-state-policy"
  description = "Policy used for terraform remote state"
  policy      = data.aws_iam_policy_document.tf_remote_state.json
}

# Attach tf remote state policy to OIDC roles
resource "aws_iam_role_policy_attachment" "be-remote-state-policy" {
  for_each   = module.oidc_role
  role       = each.value.role_name
  policy_arn = aws_iam_policy.tf_remote_state_policy.arn
}




# Permissions needed for backend OIDC role
data "aws_iam_policy_document" "backend" {
  statement {
    effect = "Allow"
    actions = [
      "iam:*",
      "apigateway:*",
      "dynamodb:*",
      "lambda:*",
      "logs:*"
    ]
    resources = ["*"]
  }
}

# All required permissions for frontend OIDC role
data "aws_iam_policy_document" "frontend" {
  statement {
    sid    = "Frontend"
    effect = "Allow"
    actions = [
      "route53:*",
      "acm:*",
      "cloudfront:*",
      "s3:*",
      "iam:*"
    ]
    resources = ["*"]
  }
}

# Create policy for OIDC roles
resource "aws_iam_policy" "oidc_role_policy" {
  for_each    = var.oidc_roles_and_subjects
  name        = "oidc-${each.key}-role-policy"
  description = "Policy used for OIDC ${each.key} CI role"
  policy      = local.oidc_policy_document[each.key].json
}

# Attach policies to OIDC roles
resource "aws_iam_role_policy_attachment" "oidc_backend_role_policy_attachment" {
  for_each   = var.oidc_roles_and_subjects
  role       = module.oidc_role[each.key].role_name
  policy_arn = aws_iam_policy.oidc_role_policy[each.key].arn
}