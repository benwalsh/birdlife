terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.34 required for aws_ecs_express_gateway_service (ECS Express Mode),
      # which the express-service module wraps.
      version = "~> 6.34"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state: fill in and `terraform init` once the S3 bucket + Dynamo lock
  # table exist. Left commented so `terraform validate` works out of the box.
  # backend "s3" {
  #   bucket         = "culfinbirds-tfstate"
  #   key            = "cloud/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "culfinbirds-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "eist-culfinbirds"
      Managed = "terraform"
    }
  }
}

# CloudFront + its ACM certificate must live in us-east-1, regardless of where
# the app runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project = "eist-culfinbirds"
      Managed = "terraform"
    }
  }
}
