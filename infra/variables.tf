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
