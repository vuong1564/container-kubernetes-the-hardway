
provider "cloudflare" {
}

provider "consul" {
}

provider "aws" {
}

provider "vault" {
}

terraform {
  required_providers {
    consul = {
      source  = "hashicorp/consul"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
    }
    aws = {
      source  = "hashicorp/aws"
    }
    vault = {
      source  = "hashicorp/vault"
    }
  }
}
