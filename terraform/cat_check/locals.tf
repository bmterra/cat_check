locals {
  region              = "eu-west-1"
  name                = "Cat Checker"
  dynamodb_table_name = "cat_checker"

  tags = {
    Name       = local.name
    Repository = "https://github.com/bmterra/cat_check"
  }
}