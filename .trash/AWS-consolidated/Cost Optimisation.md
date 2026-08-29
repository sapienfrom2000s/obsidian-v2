# Cost Optimisation

Cost is an SRE responsibility, not finance's. Two interview forms: "how do you reduce cost?" and "your bill spiked 40% — walk me through the investigation."

## EC2 levers

- **Commitment discounts** — On-Demand only for truly unpredictable load. Baseline 24/7 load → Reserved Instances (up to −72%, locked to type/region) or **Savings Plans** (up to −66%, flexible across families/regions/Fargate/Lambda — usually the right pick).
- **Right-sizing** — Compute Optimizer on CloudWatch metrics; an `m5.4xlarge` at 10% CPU → `m5.xlarge` = −75% for that instance.
- **Spot** (−90%) for fault-tolerant tiers: batch, data processing, stateless behind ASG — provided apps handle the 2-minute notice.

## RDS traps

- **Multi-AZ doubles cost** — right for production, waste in dev/staging.
- Read replicas: full instance price each; size replicas to the *read workload*, not by copying the primary.
- RDS Reserved Instances don't cross instance families — a `db.r5` reservation won't cover a `db.r6g` migration.

## NAT Gateway — the silent killer

Charges **per hour ($0.045/h) AND per GB processed ($0.045/GB)**. All S3 reads + ECR pulls + external calls through NAT = thousands/month in processing alone.

Fixes by traffic type: S3/DynamoDB → **Gateway Endpoints (free)**. ECR/CloudWatch/Secrets Manager/SQS → Interface Endpoints (cheaper than NAT at volume). Audit what remains: NAT's `BytesOutToDestination` metric → VPC Flow Logs → destination IPs → replace with endpoints.

## S3

- **Lifecycle transitions** (30d → Standard-IA, 90d → Glacier) and expiry.
- **Versioning accumulates silently** — pair with a non-current-version expiry rule, always.
- Internet egress from S3 = $0.09/GB; **CloudFront in front** is cheaper and faster (cache hits = zero origin transfer).

## "AWS bill spiked" — investigation flow

```
1. Cost Explorer → which service? which region?
2. Break down by usage type → compute? storage? data transfer?
3. Break down by resource tag → which team/app?
4. EC2:   ASG scaled out without scale-in? new instance type? Spot→On-Demand fallback?
5. NAT:   BytesOutToDestination → Flow Logs → which destinations?
6. S3:    non-current versions? egress? expensive LIST storms?
7. RDS:   new replica? Multi-AZ enabled? storage auto-growth (never shrinks)?
8. Data transfer: cross-AZ ($0.01/GB each way), cross-region, egress
```

## More traps

- **Savings Plan commitments are irrevocable** — commit only to the guaranteed 24/7 baseline; everything above stays On-Demand/Spot.
- **Cross-AZ transfer is billed even inside one VPC** — co-locate chatty compute+data in one AZ (accepting the availability tradeoff).
- **Glacier retrieval isn't free** — frequent queries on "archived for savings" data can cost more than Standard-IA. Model retrieval frequency first.
