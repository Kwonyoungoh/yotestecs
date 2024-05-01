provider "aws" {
  region = var.aws_region
  access_key = var.iam_access_key
  secret_key = var.iam_secret_key
}

provider "aws" {
  region = "us-east-1"
  access_key = var.iam_access_key
  secret_key = var.iam_secret_key
  alias = "us-east-1"
}