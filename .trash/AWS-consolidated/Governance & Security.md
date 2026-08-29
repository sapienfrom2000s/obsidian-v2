# Governance & Security

## AWS Config — configuration state recorder

| Question | Service |
|---|---|
| Who made this API call, when? | CloudTrail |
| What do the metrics look like now? | CloudWatch |
| **Is the current configuration compliant? What was it at 2am?** | **AWS Config** |

Config continuously records a configuration item per resource change → full timeline. Incident question "what changed?" → "this SG had port 22 closed at 01:50, open at 01:55."

### Config Rules & auto-remediation

Managed rules (hundreds) + custom Lambda rules evaluate resources → COMPLIANT / NON_COMPLIANT. Remediation pairs a rule with an SSM Automation document: `s3-bucket-public-read-prohibited` fires → SSM removes the public ACL within seconds, no human.

Classic managed rules: `restricted-ssh` (SG with 22 from 0.0.0.0/0), `iam-root-access-key-check`, `rds-instance-public-access-check`, `cloudtrail-enabled`.

**Rules detect, they don't prevent.** Blocking public buckets requires SCPs / bucket policy / Block Public Access — not a Config rule.

## Organizations & SCPs

### Multi-account strategy

One account for everything is an anti-pattern (blast radius, cost attribution, isolation). Standard: production / staging / dev / security-audit (CloudTrail + Config aggregation) / shared services accounts, grouped into nested **OUs** — OU policies inherit to all member accounts.

### SCPs — the correct mental model

An SCP sets the **maximum available permissions** for everyone in a member account — including that account's root. It **grants nothing**: an `s3:*` allow-list SCP still requires an IAM allow for anyone to do anything.

Key facts:
- SCPs **do not apply to the management account** — which is why it must never run workloads.
- Typical uses: region lock (data residency), deny CloudTrail/Config disablement, block risky services outside prod, deny root usage.

### Policy evaluation (definitive)

1. Explicit **Deny** anywhere → DENY (final).
2. Explicit **Allow** → ALLOW.
3. Otherwise → **implicit DENY**. Default is deny, always. Cross-account needs explicit allows on **both** sides (calling identity policy + target resource/trust policy).

## VPC at scale

### Transit Gateway vs peering

Peering is 1:1 and non-transitive. 10 VPCs fully meshed = 45 connections. **Transit Gateway** = regional hub; each VPC gets one attachment — 10 attachments for 10 VPCs — plus VPN/Direct Connect termination for hybrid. Crossover ≈ 4–5 VPCs; TGW is not free (per attachment/hour + per GB).

### Endpoints recap (which type where)

- **Gateway endpoints** — S3 and DynamoDB only; route-table entry; **free**. Never recommend Interface endpoints for these two.
- **Interface endpoints (PrivateLink)** — everything else (SQS, ECR, CloudWatch, Secrets Manager…); ENI with private IP in your subnet; hourly + per-GB cost. Motivation: keep traffic off the NAT Gateway.

**PrivateLink** also lets *you* expose your own shared services privately to other VPCs/accounts — platform team's internal APIs without peering.

### Hybrid connectivity redundancy

Direct Connect = dedicated circuit, consistent latency — but a single circuit is a single point of failure. Production pattern: **DX primary + Site-to-Site VPN failover**, both terminating on the same VGW/TGW; BGP shifts traffic automatically if DX dies.

### Network Firewall

Dedicated firewall subnet per AZ between IGW and app subnets: stateful/stateless rules, IPS, domain filtering — capabilities SGs/NACLs don't have. Ingress: IGW → NFW → ALB → app. Egress: private subnet → NFW → NAT → IGW.

## The security services — complementary, not competing

| Service | Job |
|---|---|
| **WAF** | L7 filter on CloudFront/ALB/API GW. Web ACLs, ordered rules, managed rule groups (OWASP), **rate-based rules** (block >1,000 req/5min/IP) for credential stuffing |
| **Shield Standard** | Free, automatic L3/L4 DDoS protection for CloudFront/Route 53/ELB. Does **not** cover raw EC2 |
| **Shield Advanced** | ~$3k/mo: EC2/ELB/CF/GA/R53, DDoS Response Team, and **cost protection** — reimburses attack-driven bill spikes (ASG growth, NAT traffic) |
| **GuardDuty** | **Threat detection** from VPC Flow Logs + CloudTrail + DNS logs: recon, C2/crypto-mining, odd-geography API calls, exfiltration. Not inline — analyzes logs. Finding → EventBridge → SNS/Lambda (e.g. auto-swap the SG of a compromised instance) |
| **Inspector** | **Vulnerability scanning**: EC2 CVEs, ECR images (on push + continuous re-evaluation as new CVEs drop), Lambda dependencies. Proactive; GuardDuty is reactive |
| **Macie** | ML discovery/classification of **sensitive data in S3** (PII, credentials); flags exposed/unencrypted buckets |
| **Security Hub** | Aggregates + normalizes (ASFF) findings from all of the above across the org into one dashboard + security score, in a central security account. Needs the source services enabled in each member account or the dashboard is empty |

## Shared responsibility model

**AWS: security OF the cloud** — hardware, hypervisor, managed-service engine patching (you don't patch RDS).
**You: security IN the cloud** — always: IAM, data classification/encryption choices, network controls, app security.

The more managed the service, the more shifts to AWS — EC2 (you patch the guest OS) → RDS (AWS patches the engine; you own config, data, SGs) → Lambda/S3 (you own code, IAM, bucket/encryption policy). You never fully hand it over.
