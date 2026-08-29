## General AWS Questions

Mixed question bank from [AWS Interview Questions](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-02-15-aws-interview-questions.md) — includes networking, architecture, and behavioral angles that complement [[Ops/AWS/Questions/SRE|SRE Questions]].

## IAM & Governance

<details>
<summary>1. What is SCP?</summary>
A Service Control Policy in AWS Organizations sets the <b>maximum permissions</b> for accounts in an org. It does not grant permissions — it only restricts them. Even if an IAM policy allows an action, if the SCP denies it, the action is denied. Examples: block access to specific regions, prevent deletion of critical services across all accounts.
</details>

<details>
<summary>2. Admin vs Root user?</summary>
Root is the account email owner — unrestricted, and the only identity that can do root-only actions (close account, change payment/support plan). An "admin" is an IAM user/role with AdministratorAccess: effectively full power but still subject to SCPs, permission boundaries, and unable to perform root-only tasks. Practical rule: root gets MFA and is locked away; humans use admin roles via SSO.
</details>

## Networking

<details>
<summary>3. What is a route table?</summary>
A data structure maintained by a router/host that defines how IP packets are forwarded. Entries map destination prefixes (CIDR) to a next-hop IP, outgoing interface, and metrics. On packet arrival, the device does a <b>longest-prefix match</b> to find the most specific route. Can contain static routes (manual) and dynamic routes (OSPF, BGP, RIP). View with <code>ip route show</code> or <code>route -n</code>.
</details>

<details>
<summary>4. What is ARP and how does the ARP table differ from the IP routing table?</summary>
<b>ARP table (Layer 2)</b>: IP → MAC mappings within the local network — resolves an IP to a MAC so frames can be delivered on the same subnet.
<b>IP routing table (Layer 3)</b>: destination prefix → next-hop gateway + interface, longest-prefix match — forwards packets <i>between</i> networks.
</details>

<details>
<summary>5. Internet Gateway vs NAT Gateway?</summary>
<b>IGW</b>: bidirectional VPC ↔ internet. Resources in a public subnet need a public IP + route (0.0.0.0/0 → IGW). Stateless, AWS-managed, <b>free</b>. Use when resources must be directly reachable: web servers, bastion hosts, public APIs.
<b>NAT Gateway</b>: outbound-only for private subnets. Lives in a public subnet with an Elastic IP; private subnets route 0.0.0.0/0 → NAT. A database at 10.0.2.50 can download patches or call external APIs but can never receive inbound connections. Stateful, HA within an AZ, ~$0.045/hour + per-GB.
Production uses both: public subnet (ALB/web tier, IGW) + private subnet (DBs/backends, NAT for egress). Key difference: IGW = two-way, resources exposed; NAT = one-way out, resources hidden.
</details>

<details>
<summary>6. What is the difference between a VPC and a subnet?</summary>
A VPC is your entire private network in the cloud — defines the overall IP range and is the boundary for routing, security, and isolation (your virtual data centre). A subnet is a smaller segment carved from that range, pinned to one AZ, where resources live — used to organise and isolate workloads (public subnets for web tiers, private for databases).
</details>

<details>
<summary>7. Where are route tables defined in AWS?</summary>
Inside a VPC. Each VPC has a main route table by default; you can create custom ones and associate them with specific subnets. Managed under the VPC service (VPC → Route Tables) and control traffic to the IGW, NAT Gateway, peering connections, or Transit Gateway.
</details>

<details>
<summary>8. AWS has no option to create a "public" or "private" subnet. How is it configured?</summary>
A subnet isn't inherently public or private — it's determined by its <b>route table</b>. Public = route table has 0.0.0.0/0 → IGW (and instances get public IPs). Private = no direct IGW route (outbound via NAT in a public subnet instead).
</details>

<details>
<summary>9. An EC2 machine needs to talk to the internet. What security group rules apply? Do we need an inbound rule for the response?</summary>
Outbound: allow traffic to 0.0.0.0/0 (HTTP/HTTPS as needed). <b>No inbound rule is needed</b> — security groups are <b>stateful</b>: the SG remembers the connection and auto-allows the response back in. A NACL, being stateless, would need both.
</details>

<details>
<summary>10. What is hybrid networking?</summary>
Connecting your on-premises data centre (or other clouds) with your AWS VPC so they function as one integrated network — via AWS Site-to-Site VPN (IPsec over the internet) or Direct Connect (dedicated private circuit).
</details>

<details>
<summary>11. Why use Site-to-Site VPN over the public internet?</summary>
Although it traverses the public internet, traffic is protected with IPsec encryption — Layer 3 encryption.
</details>

<details>
<summary>12. Transit Gateway vs VPC Peering?</summary>
TGW connects many VPCs, on-prem networks, and Direct Connect locations through one regional hub — single interface for all connections, simpler management at scale. Peering is a 1:1 private connection between two VPCs, non-transitive. Few VPCs → peering; many → TGW.
</details>

<details>
<summary>13. NLB vs ALB?</summary>
ALB works at Layer 7 — understands HTTP/HTTPS, does path- and host-based routing; ideal for web apps and microservices. NLB works at Layer 4 — TCP/UDP, very high performance and low latency, static IPs. HTTP app → ALB; high-performance TCP/UDP or static IP requirement → NLB.
</details>

<details>
<summary>14. Gateway Load Balancer?</summary>
GWLB transparently routes and scales traffic to virtual appliances (firewalls, IDS/IPS) at Layer 3 using GENEVE encapsulation. Use when you need centralised inline traffic inspection across VPCs without changing the application architecture.
</details>

<details>
<summary>15. How can a third party access a DB in a private subnet?</summary>
They can't reach it over the internet, so provide controlled access:
<ul>
<li><b>Network-level</b>: Site-to-Site VPN to their network; client VPN / zero-trust for individuals; bastion/jump host (prefer managed sessions like SSM); PrivateLink for enterprise private connectivity.</li>
<li><b>Service-level (often safer)</b>: expose a secured API, share a read replica, or export controlled datasets to object storage.</li>
<li>Public exposure with IP allowlisting is technically possible but discouraged.</li>
</ul>
Best choice depends on humans vs applications, and read-only vs read-write.
</details>

## Compute & Storage

<details>
<summary>16. NFS vs EFS vs EBS?</summary>
<b>NFS</b>: protocol for network filesystem sharing — multi-client with distributed locking, but latency-bound and you manage the server.
<b>EBS</b>: block storage for a <b>single</b> EC2 — sub-ms latency, predictable IOPS, single-writer; boot volumes, databases.
<b>EFS</b>: managed NFS (v4.1) — elastic, multi-AZ, concurrent multi-instance access; higher latency than EBS, expensive for throughput-heavy loads; shared content, home dirs, containers.
Pick EBS for single-instance performance, EFS for shared multi-instance access, self-managed NFS for custom/non-AWS needs.
</details>

<details>
<summary>17. EKS vs ECS vs Docker on a VM vs plain VM — when to use each?</summary>
<b>VM (EC2)</b>: maximum simplicity or OS-level control — legacy apps, stateful systems, custom drivers, few services. You manage everything.
<b>Docker on VM</b>: container packaging without an orchestrator — small teams, handful of services; transitional step before ECS/EKS.
<b>ECS (esp. Fargate)</b>: managed orchestration, minimal ops, fully on AWS — tight IAM/ALB/CloudWatch integration, simpler and cheaper than K8s.
<b>EKS</b>: when Kubernetes is a strategic requirement — multi-cloud portability, advanced scheduling, service mesh, GitOps. Most power, most cost and operational effort.
</details>

<details>
<summary>18. Problems with Lambda? Why use servers at all?</summary>
Cold start latency for time-sensitive apps; 15-minute execution cap; expensive at high sustained volume (a server is cheaper); debugging and local testing harder; state and long-lived connections (WebSockets, background jobs) awkward. Lambda shines for event-driven, spiky, sporadic workloads — servers win for always-on, stateful, compute-heavy ones.
</details>

<details>
<summary>19. API Gateway vs Application Load Balancer?</summary>
API Gateway: REST APIs, AWS service integrations, built-in auth and throttling. ALB: load balancing HTTP/HTTPS to EC2/containers at scale, no per-request pricing. High volume → ALB is cheaper (~700M req/month break-even).
</details>

## Data & Architecture

<details>
<summary>20. What is connection pooling?</summary>
Maintaining and reusing a fixed set of pre-established DB connections instead of creating/closing one per request (expensive: handshake, auth, setup). The app creates a pool at startup (min/max); requests borrow and return connections. When concurrent demand exceeds the pool, requests <b>queue</b> — no new pool is spawned — and may time out if nothing frees up, which also protects the DB from being overwhelmed. Handled by the application or DB driver (PgBouncer, RDS Proxy at scale).
</details>

<details>
<summary>21. Talk about the CAP theorem.</summary>
Consistency, Availability, Partition tolerance. <b>P is non-negotiable</b> (networks are unreliable) — so a partition forces a choice between C and A.
<b>CP</b>: rejects requests rather than serve inconsistent data — majority quorum, W + R &gt; N. Cassandra with N=5, W=3, R=3 gives strong consistency; CockroachDB enforces Raft majority automatically. PostgreSQL primary-replica has no explicit W+R control — async replicas serve stale reads.
<b>AP</b>: stays available accepting reads/writes on both sides — low quorums (W=1, R=1), conflicts resolved later via last-write-wins, vector clocks, CRDTs, or background repair. Cassandra/DynamoDB behave this way at low consistency levels.
</details>

<details>
<summary>22. Architect a fully available, fault-tolerant, scalable, secure web application.</summary>
Skeleton: Edge (CDN + WAF + DDoS) → ALB multi-AZ → stateless app servers (ASG/containers) in private subnets → managed DB Multi-AZ + read replicas + Redis cache → VPC, IAM, encryption, IaC, observability foundation.

<b>Edge</b>: CloudFront/Cloudflare caching + geo-routing (TTL strategy vs explicit invalidation); WAF OWASP rules + rate limiting — start rules in <i>count mode</i>, tune, then block; Shield absorbs volumetric attacks; Route 53 health-checked failover, RTO &lt; 60s. Breaks: stale caches post-deploy, WAF false positives.

<b>Load balancing</b>: ALB (L7) default, NLB for non-HTTP/low latency; multi-AZ target groups, cross-zone on, sane deregistration delay; <b>deep health checks</b> (DB/cache connectivity) but separate liveness from readiness so a DB outage doesn't fail every instance; target tracking on RequestCountPerTarget. Breaks: too-shallow or too-aggressive health checks, dropped requests from missing connection draining.

<b>Compute</b>: statelessness is non-negotiable — sessions in Redis, files in S3, instances disposable. Containers as default, VMs for OS control, Lambda for spiky/event-driven (not latency-sensitive). Deployments: canary (preferred, limits blast radius), blue/green (fast rollback, 2x cost), rolling (needs backward compat). On K8s: Pod Disruption Budgets, resource requests/limits, HPA. Graceful shutdown on SIGTERM — finish in-flight, then exit.

<b>Data</b>: Aurora (30s failover, 15 replicas) over RDS Multi-AZ (60–120s); Aurora Global for cross-region. Read replicas with read-your-writes routing (replication lag). Choose CP for financial data, AP for feeds/counters — explicitly. Redis cache: TTL strategy, invalidation, cache-stampede protection (probabilistic early expiry or locking). Connection pooling (PgBouncer / RDS Proxy). Backup restore <b>tested</b> weekly; know your RPO/RTO. Tiering: hot (DB+cache), warm (S3+Athena), cold (Glacier).

<b>Foundation</b>: public subnets = LBs and NAT only; apps private; DBs isolated. SGs least-privilege, NACLs second layer. IAM roles everywhere, no long-lived keys, MFA/SSO for humans, Access Analyzer. Secrets Manager with rotation, nothing in env vars/code. TLS everywhere + KMS with customer-managed keys for sensitive data. Everything IaC (Terraform/Pulumi) — console changes get reverted on next apply. Observability: structured JSON logs with correlation IDs, RED metrics + SLO alerts, distributed tracing (X-Ray/Jaeger).
</details>

<details>
<summary>23. E-commerce website — design a disaster recovery solution.</summary>
<b>Active-Passive (cold/warm standby)</b>: primary runs in one region; secondary ranges from minimal infra (cold) to fully provisioned but not serving (warm). Data continuously replicated (DB replication, object storage sync). On disaster, DNS/LB failover. Cheaper, but higher RTO and possible data loss (RPO depends on replication lag).
<b>Active-Active</b>: app live in multiple regions, traffic via global LB / geo-DNS, multi-region replication with conflict resolution. On failure, traffic shifts automatically — near-zero RTO/RPO. More complex and expensive.
</details>

<details>
<summary>24. E-commerce, HA with minimum latency, Postgres. How?</summary>
<b>Primary-Replica (streaming + auto failover)</b>: one writer, replicas for reads (listings/search), Patroni or managed failover promotes a replica. Simple and cost-effective for read-heavy workloads; write scalability is the limit.
<b>Multi-region active-active</b>: multiple regions accept writes via logical replication / distributed Postgres (Citus); traffic routed to nearest region. Great latency and availability; conflict resolution complexity.
<b>Synchronous replication cluster</b>: commits acknowledged by replicas — RPO = 0 — with automated leader election. Ideal for orders/payments; higher write latency, best within a region.
</details>

<details>
<summary>25. Best security practices at each layer — edge, LB, compute, data, foundation?</summary>
<b>Edge</b>: WAF + Shield; CloudFront to reduce origin exposure; HTTPS everywhere (ACM, HSTS); OAC so only CDN reaches origin; Route 53 logging.
<b>LB</b>: TLS termination with strong policies; WAF on ALB/API GW; SGs restricted to required ports/sources; access logs to S3 with alerts; prefer internal LBs.
<b>Compute</b>: IAM roles, least privilege, no hardcoded creds; patching + scanning (SSM, Inspector, ECR scan); Secrets Manager with rotation; private subnets, restricted egress; runtime monitoring, disable IMDSv1.
<b>Data</b>: KMS encryption at rest; TLS in transit; S3 Block Public Access + least-privilege policies; backups + PITR with tested restores; audit logs (CloudTrail data events, DB logs).
<b>Foundation</b>: multi-account org; org-wide CloudTrail to a central log archive; MFA/SSO, root locked down; SCPs; Security Hub + GuardDuty + Config for continuous compliance.
</details>

<details>
<summary>26. Best security model for a small company without spending much?</summary>
Shared responsibility + defence-in-depth using mostly-free native services: IAM hygiene (least-privilege roles, no root usage, MFA, IAM Identity Center), AWS Organizations for account structure, VPC isolation with private subnets and SGs; CloudTrail + GuardDuty + Config basic rules for visibility; Security Hub for centralised posture; S3 Block Public Access, default KMS encryption, AWS Backup; WAF + Shield Standard for public apps; SSM Patch Manager for automation. Minimal third-party spend, strong baseline.
</details>

<details>
<summary>27. What is AWS Inspector?</summary>
Scans EC2 instances, ECR container images, and Lambda functions for software vulnerabilities (CVEs) and unintended network exposure.
</details>

<details>
<summary>28. Pillars of the Well-Architected Framework?</summary>
Six: Operational Excellence (continuous improvement), Security, Reliability (fast recovery, consistent performance), Performance Efficiency (optimal resource use), Cost Optimization, and Sustainability.
</details>

## Cost & IaC

<details>
<summary>29. How do you reduce the cost of AWS services?</summary>
Reserved Instances / Savings Plans for baseline compute; Auto Scaling + ELB to match capacity to demand; Lambda for spiky/serverless workloads; Cost Explorer + Budgets for monitoring and alerts; regular usage reviews to eliminate waste.
</details>

<details>
<summary>30. CloudFormation vs Terraform — how do you choose?</summary>
CloudFormation: fully AWS-committed — deep native integration, tight IAM alignment, no extra tooling; AWS-only teams and governance-focused enterprises.
Terraform: multi-cloud/hybrid, huge provider ecosystem, modular reusable patterns, flexible state management and workflows.
Choose CFN for AWS-centric simplicity; Terraform for cross-cloud portability and flexibility.
</details>

## Behavioral

<details>
<summary>31. What does your typical day look like?</summary>
(Adapt to your own role.) Reference mix of feature development with operational involvement: backend features as the core, plus infra debugging, migrations, and environment stabilisation when issues arise — a blend of feature work and operational problem-solving.
</details>
