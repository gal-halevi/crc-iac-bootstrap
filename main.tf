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

# Create the backend role needed for CI/CD
module "oidc_backend_role" {
  source                   = "./modules/iam_oidc_role"
  role_name                = "oidc_backend_role"
  oidc_provider_arn        = aws_iam_openid_connect_provider.github_oidc_idp.arn
  oidc_subject_policy_list = var.oidc_subject_backend_list
}

# All required permissions for backend deploy/destroy
data "aws_iam_policy_document" "backend" {
  statement {
    sid    = "Backend"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:DELETE",
      "dynamodb:CreateTable",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:DeleteTable",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "lambda:AddPermission",
      "lambda:CreateFunction",
      "lambda:GetPolicy",
      "lambda:GetFunction",
      "lambda:ListVersionsByFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:DeleteFunction",
      "lambda:RemovePermission",
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:DeleteLogGroup"
    ]
    resources = ["*"]
  }
}

# All required permissions for backend tf remote state
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

# Create policy for backend
resource "aws_iam_policy" "backend_deploy_policy" {
  name        = "ci-deploy-policy"
  description = "Policy used for backend deployments on CI"
  policy      = data.aws_iam_policy_document.backend.json
}

# Create policy for backend tf remote state
resource "aws_iam_policy" "tf_remote_state_policy" {
  name        = "tf-remote-state-policy"
  description = "Policy used for terraform remote state"
  policy      = data.aws_iam_policy_document.tf_remote_state.json
}

# Attach policies for OIDC role
resource "aws_iam_role_policy_attachment" "attach-backend-deploy-policy" {
  role       = module.oidc_backend_role.role_name
  policy_arn = aws_iam_policy.backend_deploy_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach-tf-remote-state-policy" {
  role       = module.oidc_backend_role.role_name
  policy_arn = aws_iam_policy.tf_remote_state_policy.arn
}