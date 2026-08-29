# IAM — Identity & Access Management

## Why IAM exists

Every AWS API call — from your laptop, an EC2 instance, or a Lambda — must be **authenticated** (who are you?) and **authorized** (are you allowed?). IAM answers both. Without it you'd embed long-lived credentials everywhere (dangerous) or have no access control at all.

## Root account

The original account created at signup. Unrestricted access, including root-only actions (close account, change payment). The rule: **lock it away** — enable MFA, generate no access keys, use it only for root-only tasks. If root creds leak, blast radius is total.

## Users, Groups, Least Privilege

- **IAM User** — maps 1:1 to a human or long-lived service identity.
- **Group** — collection of users; attach policies to the group, members inherit them. Groups cannot contain groups.
- **Least privilege** — grant only what the job needs. Start from zero and add incrementally, never start broad and trim later.

## Policies — the core of authorization

A policy is a JSON document: what **actions** are allowed/denied on which **resources** under what **conditions**. Every API call resolves to allow or deny by evaluating all applicable policies.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-south-1"
        }
      }
    }
  ]
}
```

### The three policy types

AWS doesn't check one policy — it gathers **every** policy applying to a request and evaluates them together. The three places a decision can come from:

| | Attached to | Answers | Example |
|---|---|---|---|
| **Identity policy** | The *caller* (user, group, role) | What is the caller allowed to do? | "Priya may `s3:GetObject` on `my-bucket`" |
| **Resource policy** | The *resource* (S3 bucket policy, KMS key policy, SQS queue policy) | Who may touch this resource? | "Account 9999 may read this bucket" — this is the type used for cross-account access and public buckets |
| **SCP** | The *account* (via AWS Organizations) | What is the maximum anyone in this account may ever do? | "Deny all EC2 outside ap-south-1" — caps everyone, including the account's root |

### Policy evaluation logic (heavily asked)

1. **Explicit Deny** anywhere (SCP, resource policy, identity policy) → **DENY**. Cannot be overridden by any allow.
2. **Explicit Allow** → **ALLOW**.
3. Neither → **implicit DENY** (default).

```
SCP on her account  ────┐
Identity policy     ────┼──> all evaluated together ──> explicit deny anywhere? DENY
Bucket policy       ────┘                              else explicit allow?    ALLOW
                                                       else                   implicit DENY
```

Worked example: Priya's identity policy allows `s3:GetObject`, and the bucket policy allows her too — but the org's SCP denies S3 outside `ap-south-1`, and she's in `eu-west-1`. **DENY.** One deny beats every allow.

Same-account vs cross-account: if Priya and the bucket are in the **same account**, access is granted when *either* her identity policy *or* the bucket policy allows it — one yes is enough. **Cross-account** needs *both* sides to allow: her identity policy must let her touch the other account's bucket, AND that account's bucket policy must let her in. Like visiting your own house (your key suffices) vs someone else's house (you need permission to go AND the owner must open the door).

Trap: "Can an admin Allow something an SCP denies?" — No. SCPs are organization-level guardrails; even the account root user cannot override an SCP deny.

## Roles — the right way to give services access

A **Role** is a set of permissions that anyone *allowed to take it on* can temporarily use. Every role is made of **two policies** — remember this pair, everything about roles follows from it:

| Policy on a role | Answers |
|---|---|
| **Trust policy** | *WHO* may assume the role (the role's guest list) |
| **Permission policy** | *WHAT* the role can do once assumed |

The clearest way to see a role — compare with a user:

| | IAM User | IAM Role |
|---|---|---|
| What it is | A permanent identity (a person or service) with its own login/keys | A bundle of permissions with **no** permanent credentials |
| Credentials | Long-lived password / access key | None. Whoever assumes it gets **temporary** keys from STS (expire in 15 min – 12 hrs) |
| Used by | Humans, long-lived services | Anything that needs access *for a while*: EC2 instances, Lambdas, another AWS account |
| Analogy | A employee badge (yours, forever) | A visitor's day pass — handed to whoever is authorized, expires automatically |

So "assuming a role" = swapping your own permissions for the role's permissions, temporarily. When the temporary credentials expire, they're gone — nothing to revoke, nothing to leak.

### Why roles exist

Without them, you'd put a long-lived access key on every instance — keys leak everywhere (configs, backups, logs), revoking one means hunting down every copy, a shared key gives 50 instances identical permissions, and CloudTrail can't tell which instance acted. Temporary credentials fix all of this *by design*: they expire on their own, and each assumption is separately logged. In short — roles turn "protect a secret forever" into "let AWS check who's allowed on every request."

The classic example: an EC2 instance needs to read S3. Never put user access keys on the instance (any process with shell access can read them). Attach an IAM Role instead — the app calls the metadata endpoint (`http://169.254.169.254/latest/meta-data/iam/security-credentials/`) and gets rotating credentials automatically. You never manage a secret.

```
EC2 Instance
    │ assumes role via instance profile
    ▼
IAM Role: ec2-s3-read-role
    │ has attached policy
    ▼
Policy: Allow s3:GetObject on arn:aws:s3:::my-bucket/*
```

An **Instance Profile** is a wrapper around an IAM Role that lets it be attached to an EC2 instance — you attach the *profile* to the instance, and the instance gets the *role's* permissions. Yes, it's the IAM Role from the definition above — a role cannot be attached to EC2 directly, only through its profile. In practice the terms are used interchangeably (and the console quietly creates the profile for you), which is why they feel like one thing.

## STS and AssumeRole — cross-account access

**STS (Security Token Service)** is the AWS service that hands out temporary credentials. Calling `sts:AssumeRole` returns a temporary Access Key ID, Secret Key, and Session Token that expire after 15 min – 12 hours. When someone says "roles use short-lived credentials," STS is the thing issuing them.

Cross-account pattern: app in Account A needs a database in Account B. Create a role in B whose **trust policy** (the WHO-may-assume-me policy from the table above) allows A to assume it — B's side: the door opens. The app's own identity policy must also allow `sts:AssumeRole` on that role's ARN — A's side: permission to go. Cross-account needs *both* sides, per the rule above. The app then calls `sts:AssumeRole` and gets credentials scoped to B.

```json
// Trust policy on the role in Account B:
// "Account A (111122223333) may assume this role"
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
    "Action": "sts:AssumeRole"
  }]
}
```

## Permission boundaries

A policy attached to a user/role that sets the **maximum** permissions that identity can ever have. It does not grant anything — it caps. Platform teams use it so developers can create their own roles without escalating to admin.

**Example**: developers create their own roles; platform team attaches this boundary to each one:

```json
// Permission boundary — the ceiling
{ "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*", "dynamodb:*", "sqs:*", "logs:*"],
    "Resource": "*"
}]}
```

| Layer | Written by | Answers |
|---|---|---|
| Identity policy | Developer | What is the role *granted*? |
| Permission boundary | Platform team | What is the role *capable of*, ever? |

**Effective permissions = identity policy ∩ boundary.** A developer role with `"Action": "*"` still only gets S3/DynamoDB/SQS/logs — everything outside the cap is inert. A ceiling, not a grant. (SCP = ceiling on a whole *account*; boundary = ceiling on one *role/user* — neither grants anything.)
