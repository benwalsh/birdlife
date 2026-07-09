variable "aws_region" {
  description = "Primary region for App Runner + RDS."
  type        = string
  default     = "eu-west-1"
}

variable "domain_name" {
  description = "Public apex domain served by CloudFront."
  type        = string
  default     = "culfinbirds.net"
}

variable "image_tag" {
  description = "ECR image tag App Runner deploys (push the Docker image with this tag)."
  type        = string
  default     = "latest"
}

variable "db_username" {
  description = "RDS MySQL master username."
  type        = string
  default     = "eist"
}

variable "db_name" {
  description = "Database name inside RDS (the app's DB_NAME)."
  type        = string
  default     = "eist"
}

variable "db_instance_class" {
  description = "RDS instance class — a small ARM Graviton box; it's a derived mirror, not the source of truth."
  type        = string
  default     = "db.t4g.micro"
}

variable "container_port" {
  description = "Port the Rails/Puma container listens on."
  type        = number
  default     = 3000
}

variable "github_repository" {
  description = "owner/name of the GitHub repo allowed to deploy via OIDC."
  type        = string
  default     = "benwalsh/birdlife"
}

variable "google_client_id" {
  description = "Google OAuth client ID. Set in infrastructure/terraform.tfvars (gitignored) or TF_VAR_google_client_id."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret. Set in infrastructure/terraform.tfvars (gitignored) or TF_VAR_google_client_secret."
  type        = string
  sensitive   = true
}
