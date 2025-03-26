variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN (needs to be created first with aws_iam_openid_connect_provider)"
}

variable "oidc_subject_policy_list" {
  type        = list(string)
  description = "Define who can assume this role"
}