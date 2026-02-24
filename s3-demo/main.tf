terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Add this backend block to store state in AWS S3
  backend "s3" {
    bucket = "rajaram-terraform-state"
    key    = "atlantis-demo/terraform-atlantis-demo.tfstate"
    region = "ap-south-1"
  }
}
provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 5
}

resource "aws_s3_bucket" "atlantis_demo" {
  bucket = "atlantis-demo-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Atlantis Production ECS Demo"
    Environment = "Production"
    ManagedBy   = "Atlantis on ECS"
  }
}

resource "aws_s3_bucket" "atlantis_ecs" {
  bucket = "atlantis-ecs-test-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Atlantis Webhook Test"
    Environment = "Dev"
  }
}
