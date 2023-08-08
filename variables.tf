variable "environment" {
  description = "the type of environment to deploy resources (dev/test/staging/prod)"
  default = "dev"
  type = string
}

variable "access_key" {
  description = "aws access key"
  type = string
}

variable "secret_key" {
  description = "aws secret key"
  type = string
}

variable "region" {
  description = "the aws region where the resources will be deployed"
  default = "us-east-1"
  type = string
}

variable "vpc_cidr" {
  description = "cidr block value for a vpc in the region"
  default = "10.0.0.0/16"
  type = string
}

variable "container_image" {
  description = "a container image hosted in the aws ECR repo"
  type = string
}

variable "aws_cm_cert_id" {
  description = "aws certificate manager certificate id (assumed that has been already created for a domain name)"
  type = string
}

variable "default_tags" {
  default     = {}
  description = "default tags to resources"
}
