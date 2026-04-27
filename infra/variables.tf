variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "innovation"
}

variable "instance_name" {
  description = "Name for the Lightsail instance and related resources"
  type        = string
  default     = "coder-claude"
}

variable "bundle_id" {
  description = "Lightsail bundle (instance size). large_3_0 = 2 vCPU, 8GB RAM, 160GB SSD (~$40/mo)"
  type        = string
  default     = "large_3_0"
  # Other options:
  # medium_3_0  = 2 vCPU, 4GB RAM  (~$20/mo)
  # xlarge_3_0  = 4 vCPU, 16GB RAM (~$80/mo)
}
