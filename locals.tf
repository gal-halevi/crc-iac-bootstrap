locals {
  oidc_policy_document = {
    backend  = data.aws_iam_policy_document.backend
    frontend = data.aws_iam_policy_document.frontend
  }
}