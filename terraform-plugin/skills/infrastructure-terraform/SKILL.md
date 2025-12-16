---
name: infrastructure-terraform
description: |
  Infrastructure as Code with Terraform including HCL configuration, state management,
  modular design, and plan-apply workflows. Covers cloud and on-prem resource provisioning,
  remote backends, and Terraform modules.
  Use when user mentions Terraform, HCL, terraform plan, terraform apply, tfstate,
  infrastructure as code, or IaC provisioning.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite
---

# Infrastructure Terraform

Expert knowledge for Infrastructure as Code using Terraform with focus on declarative HCL, state management, and resilient infrastructure.

## Core Expertise

**Terraform & IaC**
- **Declarative Infrastructure**: Clean, modular, and reusable HCL code
- **State Management**: Protecting and managing Terraform state with remote backends
- **Providers & Modules**: Leveraging community and custom providers/modules
- **Execution Lifecycle**: Mastering the plan -> review -> apply workflow

## Infrastructure Provisioning Process

1. **Plan First**: Always generate `terraform plan` and review carefully before changes
2. **Modularize**: Break down infrastructure into reusable and composable modules
3. **Secure State**: Use remote backends with locking to protect state file
4. **Parameterize**: Use variables and outputs for flexible and configurable infrastructure
5. **Destroy with Caution**: Double-check plan before running `terraform destroy`

## Essential Commands

```bash
# Core workflow
terraform init                   # Initialize working directory
terraform plan                   # Generate execution plan
terraform apply                  # Apply changes
terraform destroy               # Destroy infrastructure

# State management
terraform state list            # List all resources
terraform state show <resource> # Show specific resource
terraform state pull > backup.tfstate  # Backup state

# Validation and formatting
terraform validate              # Validate configuration
terraform fmt -recursive        # Format all files
terraform graph | dot -Tsvg > graph.svg  # Dependency graph

# Debugging
export TF_LOG=DEBUG             # Enable debug logging
terraform plan -out=tfplan      # Save plan for review
terraform show tfplan           # View saved plan
```

## Best Practices

**Module Structure**
```hcl
module "vpc" {
  source  = "./modules/vpc"
  version = "1.0.0"

  vpc_cidr = var.vpc_cidr
  environment = var.environment
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

**Variable Configuration**
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

**Remote State Backend**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**Provider Configuration**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
}
```

## Key Debugging Techniques

**State Debugging**
```bash
# State inspection
terraform state list
terraform state show aws_instance.web

# State recovery
terraform refresh
terraform plan -refresh-only
terraform import aws_instance.existing i-1234567890
```

**Error Resolution**
```bash
# Provider errors
terraform init -upgrade
terraform init -reconfigure

# Resource conflicts
terraform taint aws_instance.broken
terraform apply -target=aws_instance.web
```

For detailed debugging patterns, advanced module design, CI/CD integration, and troubleshooting strategies, see REFERENCE.md.
