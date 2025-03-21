variable "aws_region" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "dynamodb_table" {
  type = string
}

variable "oidc_subject_backend_list" {
  type = list(string)
}