variable "aws_region" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "dynamodb_table" {
  type = string
}

variable "oidc_roles_and_subjects" {
  type = map(list(string))
}