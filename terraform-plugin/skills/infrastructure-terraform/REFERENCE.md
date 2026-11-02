# Infrastructure Terraform Reference

Comprehensive reference for Terraform state management, module design, cloud provider patterns, Terraform Cloud/Enterprise, and advanced HCL.

## Table of Contents

- [State Management Best Practices](#state-management-best-practices)
- [Module Design Patterns](#module-design-patterns)
- [Cloud Provider Specifics](#cloud-provider-specifics)
- [Terraform Cloud & Enterprise](#terraform-cloud--enterprise)
- [Advanced HCL Patterns](#advanced-hcl-patterns)
- [Testing Strategies](#testing-strategies)
- [Security & Compliance](#security--compliance)
- [CI/CD Integration](#cicd-integration)

---

## State Management Best Practices

### Remote State Configuration

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    kms_key_id     = "arn:aws:kms:us-east-1:ACCOUNT:key/KEY-ID"
  }
}

# Azure backend
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state"
    storage_account_name = "tfstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

# GCS backend
terraform {
  backend "gcs" {
    bucket = "my-terraform-state"
    prefix = "terraform/state"
  }
}
```

### State Locking

```hcl
# DynamoDB table for state locking (AWS)
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "terraform-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "prod"
  }
}
```

### Workspaces

```bash
# List workspaces
terraform workspace list

# Create workspace
terraform workspace new staging

# Select workspace
terraform workspace select prod

# Show current workspace
terraform workspace show

# Use workspace in configuration
resource "aws_instance" "example" {
  tags = {
    Environment = terraform.workspace
  }
}
```

### State Migration

```bash
# Pull current state
terraform state pull > terraform.tfstate.backup

# Change backend configuration
# Edit backend.tf

# Reinitialize with new backend
terraform init -migrate-state

# Verify state
terraform state list
```

### Import Existing Resources

```bash
# Import resource
terraform import aws_instance.example i-1234567890abcdef0

# Import with workspace
terraform import -var-file=prod.tfvars aws_instance.example i-123456

# Import state
terraform import module.vpc.aws_vpc.main vpc-123456
```

### State Operations

```bash
# List resources
terraform state list

# Show resource
terraform state show aws_instance.example

# Move resource
terraform state mv aws_instance.old aws_instance.new

# Remove resource from state
terraform state rm aws_instance.example

# Replace provider
terraform state replace-provider registry.terraform.io/hashicorp/aws \
  registry.terraform.io/custom/aws
```

---

## Module Design Patterns

### Module Structure

```
terraform-aws-vpc/
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── examples/
│   ├── complete/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── simple/
│       └── main.tf
└── modules/
    ├── subnets/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── nat-gateway/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Input Variables

```hcl
# variables.tf
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required."
  }
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "subnet_configuration" {
  description = "Subnet configuration"
  type = object({
    public_subnets  = list(string)
    private_subnets = list(string)
    database_subnets = list(string)
  })
}
```

### Outputs

```hcl
# outputs.tf
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = aws_eip.nat[*].public_ip
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}
```

### Locals

```hcl
# locals.tf
locals {
  # Common tags
  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      Environment = var.environment
      Module      = "vpc"
    }
  )

  # Computed values
  availability_zone_count = length(var.availability_zones)

  # Subnet calculations
  public_subnet_cidrs = [
    for i in range(local.availability_zone_count) :
    cidrsubnet(var.vpc_cidr, 8, i)
  ]

  private_subnet_cidrs = [
    for i in range(local.availability_zone_count) :
    cidrsubnet(var.vpc_cidr, 8, i + local.availability_zone_count)
  ]

  # Name prefix
  name_prefix = "${var.project}-${var.environment}"
}
```

### Versioning

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
```

### Module Composition

```hcl
# main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  depends_on = [module.vpc]
}
```

---

## Cloud Provider Specifics

### AWS Patterns

```hcl
# VPC with Subnets
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

# EC2 Instance with User Data
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    hostname = "web-${count.index}"
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name_prefix}-web"
  }
}

# S3 Bucket with Encryption
resource "aws_s3_bucket" "data" {
  bucket = "${local.name_prefix}-data"

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.id
    }
  }
}
```

### GCP Patterns

```hcl
# GCP VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.project}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# GCP Subnet
resource "google_compute_subnetwork" "subnet" {
  count = length(var.regions)

  name          = "${var.project}-subnet-${var.regions[count.index]}"
  ip_cidr_range = cidrsubnet(var.vpc_cidr, 8, count.index)
  region        = var.regions[count.index]
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(var.vpc_cidr, 4, count.index + 1)
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.vpc_cidr, 8, count.index + 128)
  }
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project}-gke"
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.subnet[0].name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}
```

### Azure Patterns

```hcl
# Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project}-rg"
  location = var.location

  tags = local.common_tags
}

# Azure VNet
resource "azurerm_virtual_network" "main" {
  name                = "${var.project}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# Azure Subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 0)]

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.project

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.internal.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }
}
```

---

## Terraform Cloud & Enterprise

### Workspace Configuration

```hcl
# Terraform Cloud Backend
terraform {
  cloud {
    organization = "my-org"

    workspaces {
      name = "my-app-prod"
    }
  }
}

# Multiple workspaces
terraform {
  cloud {
    organization = "my-org"

    workspaces {
      tags = ["app:myapp", "env:prod"]
    }
  }
}
```

### VCS Integration

```hcl
# Workspace with VCS
resource "tfe_workspace" "app" {
  name         = "my-app-prod"
  organization = var.tfe_organization

  vcs_repo {
    identifier     = "my-org/my-app-infra"
    oauth_token_id = var.tfe_oauth_token_id
    branch         = "main"
  }

  working_directory = "terraform/prod"
  terraform_version = "1.5.0"

  trigger_prefixes = [
    "terraform/prod"
  ]

  auto_apply = false
}
```

### Sentinel Policies

```python
# policy.sentinel
import "tfplan/v2" as tfplan

# Require all resources to have tags
main = rule {
  all tfplan.resource_changes as _, resource {
    resource.change.after.tags contains "Environment" and
    resource.change.after.tags contains "Owner"
  }
}

# Enforce encryption
aws_s3_encryption = rule {
  all tfplan.resource_changes as _, resource {
    resource.type is "aws_s3_bucket" implies
      resource.change.after.server_side_encryption_configuration is not null
  }
}
```

### Cost Estimation

```hcl
# workspace.tf
resource "tfe_workspace" "app" {
  name         = "my-app-prod"
  organization = var.tfe_organization

  # Enable cost estimation
  assessments_enabled = true

  # Set cost estimation threshold
  cost_estimation_enabled = true
}
```

---

## Advanced HCL Patterns

### Dynamic Blocks

```hcl
# Dynamic ingress rules
resource "aws_security_group" "web" {
  name   = "${local.name_prefix}-web-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = lookup(ingress.value, "description", "")
    }
  }

  # Multiple dynamic blocks
  dynamic "egress" {
    for_each = var.egress_rules
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}

# Usage
ingress_rules = [
  {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  },
  {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
]
```

### For Each

```hcl
# Create multiple subnets
resource "aws_subnet" "private" {
  for_each = {
    for idx, az in var.availability_zones :
    az => {
      cidr_block = cidrsubnet(var.vpc_cidr, 8, idx)
      az         = az
    }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = {
    Name = "${local.name_prefix}-private-${each.key}"
    Type = "private"
  }
}

# Reference outputs
output "private_subnet_ids" {
  value = { for k, v in aws_subnet.private : k => v.id }
}
```

### Count vs For Each

```hcl
# Using count (index-based)
resource "aws_instance" "web" {
  count = 3

  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-web-${count.index}"
  }
}

# Using for_each (key-based, more stable)
resource "aws_instance" "web" {
  for_each = toset(var.instance_names)

  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[index(var.instance_names, each.key)].id

  tags = {
    Name = "${local.name_prefix}-${each.key}"
  }
}
```

### Conditional Resources

```hcl
# Create resource only if condition is met
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-${count.index}"
  }
}

# Conditional values
resource "aws_instance" "web" {
  instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"
  monitoring    = var.environment == "prod" ? true : false
}
```

### Complex Expressions

```hcl
# Flatten nested structures
locals {
  # Input: list of objects with nested lists
  security_group_rules = flatten([
    for sg in var.security_groups : [
      for rule in sg.rules : {
        sg_name  = sg.name
        rule_type = rule.type
        from_port = rule.from_port
        to_port   = rule.to_port
        protocol  = rule.protocol
        cidr_blocks = rule.cidr_blocks
      }
    ]
  ])

  # Merge maps with priority
  merged_tags = merge(
    var.default_tags,
    var.environment_tags,
    var.custom_tags,
    {
      Managed_by = "Terraform"
    }
  )

  # Conditional map merge
  all_tags = merge(
    local.common_tags,
    var.enable_monitoring ? { Monitoring = "enabled" } : {}
  )
}
```

---

## Testing Strategies

### Terratest (Go)

```go
// test/terraform_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCCreation(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../examples/complete",
        Vars: map[string]interface{}{
            "vpc_cidr": "10.0.0.0/16",
            "availability_zones": []string{"us-east-1a", "us-east-1b"},
        },
    })

    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)

    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)

    publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
    assert.Equal(t, 2, len(publicSubnets))
}
```

### Validation Rules

```hcl
variable "vpc_cidr" {
  type = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "VPC CIDR block must be /28 or larger."
  }
}

variable "instance_type" {
  type = string

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "Instance type must be t3.micro, t3.small, or t3.medium."
  }
}
```

### Static Analysis

```bash
# TFLint
tflint --init
tflint

# .tflint.hcl
plugin "aws" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "aws_instance_invalid_type" {
  enabled = true
}

# Checkov (security scanning)
checkov -d .

# TFSec (security scanning)
tfsec .

# Terraform validate
terraform validate

# Terraform fmt (check)
terraform fmt -check -recursive

# Custom validation script
#!/bin/bash
terraform fmt -check -recursive || exit 1
terraform validate || exit 1
tflint || exit 1
checkov -d . --quiet || exit 1
```

---

## Security & Compliance

### Secrets Management

```hcl
# Use external secrets (AWS Secrets Manager)
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/db/password"
}

resource "aws_db_instance" "main" {
  engine         = "postgres"
  instance_class = "db.t3.micro"

  username = "admin"
  password = data.aws_secretsmanager_secret_version.db_password.secret_string

  # Never use:
  # password = var.db_password  # Bad: in state file  # pragma: allowlist secret
  # password = "hardcoded"      # Bad: in source code  # pragma: allowlist secret
}

# Use sensitive variables
variable "api_key" {
  type      = string
  sensitive = true
}

# Mark outputs as sensitive
output "connection_string" {
  value     = "postgresql://${aws_db_instance.main.username}:${aws_db_instance.main.password}@${aws_db_instance.main.endpoint}"
  sensitive = true
}
```

### Policy as Code

```hcl
# OPA Policy (Rego)
# policy.rego
package terraform.analysis

import input as tfplan

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_s3_bucket"
    not resource.change.after.server_side_encryption_configuration

    msg := sprintf("S3 bucket '%s' must have encryption enabled", [resource.address])
}

deny[msg] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_instance"
    resource.change.after.monitoring == false

    msg := sprintf("EC2 instance '%s' must have detailed monitoring enabled", [resource.address])
}
```

### Drift Detection

```bash
# Manual drift detection
terraform plan -detailed-exitcode

# Exit codes:
# 0 = No changes
# 1 = Error
# 2 = Successful plan with changes (drift detected)

# Automated drift detection (Terraform Cloud)
# Runs automatically or via API

# Using AWS Config for drift
resource "aws_config_configuration_recorder" "main" {
  name     = "terraform-drift"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
  }
}
```

---

## CI/CD Integration

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - plan
  - apply

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/terraform
  TF_VERSION: 1.5.0

.terraform:
  image:
    name: hashicorp/terraform:$TF_VERSION
    entrypoint: [""]
  before_script:
    - cd ${TF_ROOT}
    - terraform init

validate:
  extends: .terraform
  stage: validate
  script:
    - terraform fmt -check -recursive
    - terraform validate
    - tflint

plan:
  extends: .terraform
  stage: plan
  script:
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - ${TF_ROOT}/tfplan

apply:
  extends: .terraform
  stage: apply
  script:
    - terraform apply tfplan
  when: manual
  only:
    - main
  dependencies:
    - plan
```

### GitHub Actions

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4.4.0

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2.0.3
        with:
          terraform_version: 1.5.0

      - name: Terraform Format
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -no-color
        if: github.event_name == 'pull_request'

      - name: Terraform Apply
        run: terraform apply -auto-approve
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

### Environment Promotion

```bash
# Directory structure
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── backend.tf
│       └── terraform.tfvars
└── modules/
    └── app/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf

# Promotion workflow
# 1. Apply to dev
cd environments/dev
terraform apply

# 2. Test in dev
# run tests...

# 3. Apply to staging
cd ../staging
terraform apply

# 4. Test in staging
# run tests...

# 5. Apply to prod (manual approval)
cd ../prod
terraform apply
```

---

## Additional Resources

- **Terraform Documentation**: https://www.terraform.io/docs
- **Terraform Registry**: https://registry.terraform.io/
- **Terraform Best Practices**: https://www.terraform-best-practices.com/
- **Terratest Documentation**: https://terratest.gruntwork.io/
- **Terraform Cloud**: https://cloud.hashicorp.com/products/terraform
- **HCL Language Reference**: https://www.terraform.io/language
