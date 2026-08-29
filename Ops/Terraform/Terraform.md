# Terraform

Part of Ops notes. Related: [[DevSecOps]] (IaC security, CI/CD with Terraform).

## The Problem

How to create cloud resources (e.g. an S3 bucket with specific settings)? Three approaches:

1. Click through the cloud console UI. Easiest short term, hardest to maintain long term.
2. Call cloud APIs programmatically. Imperative: you write every step.
3. Declarative templates (CloudFormation on AWS, ARM on Azure, Deployment Manager on GCP). You describe the desired state, the tool figures out the steps.

Problem with option 3: each cloud has its own templating system. A company using multiple clouds must learn and maintain three different systems.

Terraform solves this: one IaC tool, one syntax (HCL, HashiCorp Configuration Language), works across AWS, Azure, GCP and others. Alternatives: Pulumi, Crossplane.

## Core Commands

- `terraform init`: prepares the working directory. Downloads provider plugins into `.terraform/`, verifies the backend connection (where state will be stored), and downloads modules.
- `terraform plan`: shows what changes would be made. Compares three things: your configuration (.tf files), the state file, and the real infrastructure. Changes nothing.
- `terraform apply`: executes the plan. Creates, updates or destroys real resources, then updates the state file.

Typical CI flow: plan runs on pull requests so reviewers see the changes, apply runs only after approval or merge.

## Key Files

- `.terraform.lock.hcl`: lock file. Records exact provider versions and checksums so every machine installs the same versions. Like a package lock file.
- `terraform.tfstate`: state file. Records everything Terraform manages: resource IDs, attributes, metadata. This is how Terraform knows what already exists.
- `.lock.info`: temporary file tracking who currently holds the state lock (who is running an apply right now).

Without a state file Terraform would not know what it created before, might recreate existing resources, and would have to query the entire cloud on every run.

Why not store state in Git: state can contain sensitive data, Git has no locking (simultaneous updates corrupt it), and frequent updates mean constant merge conflicts.

Solution: remote backends.

## State and Backends

Local state (default) only exists on one machine, so teammates can't see the latest changes. Two applies from two machines means duplicate resources or drift.

Remote backend: state stored in a shared system. Example, S3 with DynamoDB for locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-prod"
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```

- bucket: where the state file lives
- key: path to the state file inside the bucket
- region: region of the bucket
- dynamodb_table: used for state locking

State locking: only one Terraform operation can run against the state at a time. When apply starts, a lock entry is created (in DynamoDB, Postgres, etc.); others must wait until it is released. Note: S3 alone cannot lock, that is why DynamoDB is paired with it.

## Providers

A provider is a plugin that lets Terraform talk to an external platform (AWS, Azure, GCP, Kubernetes, Datadog...). Three kinds:

- Official: maintained by HashiCorp (e.g. hashicorp/aws)
- Partner: maintained by verified companies, published on the Terraform Registry (e.g. datadog/datadog)
- Community: maintained by independent developers, reliability varies

Multi-region: multiple provider blocks with aliases. Each resource picks its provider:

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_s3_bucket" "west_bucket" {
  provider = aws.west
  bucket   = "west-bucket-demo"
}
```

Hybrid cloud: same idea with different providers (aws + google) in one configuration, resources in both clouds.

## Variables and Outputs

- Input variables: pass values into the configuration, making it reusable. Given via CLI, tfvars files, or defaults.

```hcl
variable "bucket_name" {
  type = string
}

resource "aws_s3_bucket" "example" {
  bucket = var.bucket_name
}
```

- Output variables: expose useful values after apply (resource IDs, URLs, IPs), shareable between modules.

```hcl
output "bucket_name" {
  value = aws_s3_bucket.example.bucket
}
```

- `.tfvars` files: values for input variables, separated from the configuration. Terraform auto-loads `terraform.tfvars`. Use cases: different values per environment (dev, staging, prod), secrets kept out of main code, reuse of the same code across teams.

## Built-in Functions

Compute values instead of hardcoding them:

- conditionals: `var.env == "prod" ? 3 : 1`
- `length()`: number of elements in a list or string
- `lookup()`: get a value from a map by key
- `concat()`: combine lists
- `format()`: build strings, e.g. `format("%s-%s", var.env, "bucket")`

## Directory Structure

Terraform auto-loads all `.tf` files in a directory. Common split:

- `main.tf`: primary resources
- `providers.tf`: provider definitions
- `variables.tf`: input variable declarations
- `outputs.tf`: output variables
- `terraform.tfvars`: values for the variables

## Modules

Why: infrastructure patterns repeat (every service needs a VPC, security groups, buckets...). Copy-pasting the same code per environment means duplication, inconsistency, and harder changes.

A module is a reusable container of Terraform configuration: define the pattern once, reuse it with different inputs.

Instead of two near-identical bucket resources, one module used twice:

```hcl
module "logs_dev" {
  source      = "./modules/s3_bucket"
  bucket_name = "app-dev-logs"
  env         = "dev"
}

module "logs_prod" {
  source      = "./modules/s3_bucket"
  bucket_name = "app-prod-logs"
  env         = "prod"
}
```

Terraform Registry: public repository of providers and modules. Reuse well-tested community modules instead of writing common patterns from scratch:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
}
```

## Provisioners

Terraform creates infrastructure, but new servers are often not usable until configured (packages installed, services started). Provisioners bridge that gap with one-off setup steps. Use them sparingly: less reliable (network timing, SSH failures), harder to make idempotent.

Three kinds:

- `file`: copies files from your machine to the remote instance. Needs a connection block (SSH or WinRM).
- `remote-exec`: runs commands on the remote instance (install packages, start services). Needs a connection block.
- `local-exec`: runs commands on the machine where Terraform itself runs. No connection needed. Good for notifications or local tooling.

Alternatives, in recommended order:
1. `user_data` (cloud-init) for basic first-boot setup
2. Ansible/Chef/Puppet for full configuration management
3. Image baking with Packer (instances start ready)
4. Provisioners only as a last resort

When provisioners still make sense: a tiny one-time step where Ansible is overkill, no cloud-init hook available, or local side effects via `local-exec`.

## Taint

`taint` marks a resource as unhealthy: Terraform will destroy and recreate it on the next apply.

- Automatic: a provisioner fails during creation, so Terraform taints the resource itself
- Manual: an engineer sees a misconfigured instance and forces recreation

```bash
terraform apply -replace="aws_instance.web"
```

Internally: the state file gets a tainted flag, nothing changes yet. The next plan reads the flag and proposes destroy plus create for that resource.

## Mind Map

See [[Excalidraw/Terraform Mind Map.excalidraw.md|Terraform Mind Map]] for a quick revision of this note.
