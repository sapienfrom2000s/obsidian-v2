---
tags: [aws, architecture, ops]
---

# Three-Tier Architecture on AWS

![[Excalidraw/AWS Three-Tier Architecture.excalidraw.md|100%]]

## Summary

A highly available three-tier architecture deployed across **two Availability Zones** inside a single VPC (`10.0.0.0/16`).

### Tier 1 — Presentation (Web/Delivery)
- **Route 53** resolves DNS for the public endpoint.
- **CloudFront** (CDN) caches static content and serves assets from **Amazon S3** at the edge.
- **Internet Gateway** is the VPC's entry point for internet traffic.
- **Public subnets** (one per AZ) host a spanning **Application Load Balancer** and **NAT Gateways** for outbound traffic from private subnets.
- **Web servers (EC2, Auto Scaling Group)** run in private subnets — never directly exposed to the internet.

### Tier 2 — Application
- **App servers (EC2 in Auto Scaling Groups)** in private subnets per AZ, scaling on demand.
- Only reachable from the web tier (security groups restrict ALB → app traffic).
- Credentials/config pulled from **AWS Secrets Manager**.

### Tier 3 — Data
- **Amazon RDS in Multi-AZ deployment**: primary in AZ A, synchronous standby in AZ B with automatic failover.
- **ElastiCache (Redis)**: primary + read replica for sessions and caching, offloading the database.

### Traffic Flow
1. Users → Route 53 → CloudFront (static assets served from S3 via cache)
2. Dynamic requests: CloudFront → IGW → ALB, or users hit the IGW → ALB directly (bypassing CDN)
3. ALB routes to healthy web servers across both AZs
4. Web tier → App tier (internal)
5. App tier → RDS / ElastiCache (data subnets)

### Internet Gateway
- No IP of its own — never a packet destination.
- Route 53 resolves to the **ALB's public IP**; AWS routes it to this VPC.
- IGW does 1:1 NAT: public IP → ALB private IP.

### High Availability & Operations
- Every tier is duplicated across two AZs — the architecture survives a full AZ failure.
- Auto Scaling replaces unhealthy instances; ALB health checks route around them.
- **CloudWatch** monitors metrics, logs, and alarms across all tiers.
- Data tier subnets have no route to the internet; outbound access (patching, etc.) goes through NAT Gateways.

## Drawing
- Source: [[Excalidraw/AWS Three-Tier Architecture.excalidraw.md|AWS Three-Tier Architecture (Excalidraw)]]
