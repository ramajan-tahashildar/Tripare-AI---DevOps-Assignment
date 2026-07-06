terraform {
  backend "s3" {
    bucket         = "my-terraform-state-prod"
    key            = "hotel-booking/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock-prod"
    encrypt        = true
  }
}
