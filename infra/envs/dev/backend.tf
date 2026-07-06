terraform {
  backend "s3" {
    bucket         = "my-terraform-state-dev"
    key            = "hotel-booking/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock-dev"
    encrypt        = true
  }
}
