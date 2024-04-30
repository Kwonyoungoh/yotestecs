variable "project_name" {
  type = string
  description = "Project_name"
}

variable "aws_region" {
  type    = string
  description = "The AWS region to deploy resources into"
}

variable "vpc_cidr" {
  type    = string
  description = "CIDR block for the VPC"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  description = "List of CIDR blocks for the private subnets"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  description = "List of CIDR blocks for the public subnets"
}

variable "iam_access_key" {
  type = string
  description = "Access key for Authentication."
}

variable "iam_secret_key" {
  type = string
  description = "Secret key for Authentication."
}

variable "rds_username" {
  type = string
  description = "rds username for Authentication."
}

variable "rds_secret" {
  type = string
  description = "rds secret for Authentication."
}

variable "github_repository" {
  type = string
  description = "Secret key for Authentication."
}

variable "domain" {
  type = string
  description = "Secret key for Authentication."
}

variable "azs" {
  type    = list(string)
  description = "A list of availability zones in the region"
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}