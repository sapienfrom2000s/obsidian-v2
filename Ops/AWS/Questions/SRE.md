## SRE AWS Questions

Scenario questions and gotchas from [[Ops/AWS/AWS|AWS notes]].

## IAM

<details>
<summary>1. What is the exact order of AWS policy evaluation?</summary>
1. Explicit Deny anywhere (SCP, resource policy, identity policy) → DENY. Cannot be overridden by any allow.
2. Explicit Allow → ALLOW.
3. Neither → implicit DENY (default).
</details>

<details>
<summary>2. Can an account admin Allow something that an SCP denies?</summary>
No. SCPs are organization-level guardrails. Even the account's root user cannot override an SCP deny.
</details>

<details>
<summary>3. What's the difference between a role's trust policy and its permission policy?</summary>
Trust policy says WHO can assume the role (the principal). Permission policy says WHAT the role can do once assumed. Both must be correct for cross-account access to work.
</details>

<details>
<summary>4. "I set a permission boundary so the role now has those permissions." Correct?</summary>
No. Permission boundaries do not grant permissions — they CAP them. The role cannot exceed the boundary regardless of what other policies grant, but a boundary alone gives nothing.
</details>

<details>
<summary>5. Why create different roles for different permissions and attach them to services, instead of one role with all permissions slapped onto it?</summary>
Principle of least privilege: each service gets only what it needs, so a compromised service has a small blast radius. Roles issue short-lived credentials via STS, and separate roles make auditing and revocation per-service trivial. One mega-role means every service can do everything.
</details>

## VPC & Networking

<details>
<summary>1. How do you write a security group rule? What are the parameters?</summary>
Type/protocol (TCP, UDP, ICMP), port range, and source (inbound) or destination (outbound) — a CIDR block, another security group ID, or a prefix list. Optionally a description. Rules are Allow-only (no explicit Deny) and stateful: return traffic is automatically allowed.
</details>

<details>
<summary>2. How do you connect to an EC2 instance in a private subnet?</summary>
Via a bastion host (jump box) in a public subnet — SSH to the bastion, then to the private instance. Alternatives: AWS Systems Manager Session Manager (no inbound ports or bastion needed), or VPN/Direct Connect into the VPC.
</details>

<details>
<summary>3. Does NAT Gateway accept incoming traffic? Can someone initiate traffic from outside via NAT Gateway?</summary>
No. NAT is one-directional — it translates private IPs to the NAT's public IP for outbound traffic and maps responses back. Unsolicited inbound connections are dropped.
</details>

<details>
<summary>4. Why are RAM and disk usage not default CloudWatch metrics for EC2?</summary>
CloudWatch only sees what the hypervisor exposes: CPU, network, disk I/O. Memory utilisation and disk space live inside the guest OS, so the CloudWatch Agent must be installed on the instance to collect and publish them.
</details>

<details>
<summary>5. What security group rule should be added to a database in a private subnet so applications can access it? You can't hardcode — multiple stateless app instances are running.</summary>
Inbound rule on the DB port (e.g. 3306/5432) with the SOURCE set to the application tier's security group ID, not an IP. SG-to-SG referencing automatically covers every instance using that SG, so the app fleet can scale freely.
</details>

<details>
<summary>6. How do you write a route table rule? What are the parameters?</summary>
Destination CIDR + Target. The target can be the Internet Gateway, NAT Gateway, VPC peering connection, VPC endpoint, Transit Gateway, ENI, or the built-in local route. Most specific route wins; the local route (VPC CIDR → local) always exists and can't be removed.
</details>

<details>
<summary>7. My EC2 instance in a private subnet can't reach the internet. Walk through your troubleshooting.</summary>
1. Does the private subnet's route table have a 0.0.0.0/0 → NAT route?
2. Is the NAT Gateway itself in a public subnet?
3. Does that public subnet's route table have 0.0.0.0/0 → IGW?
4. Does the instance's Security Group allow the outbound traffic?
All four must be true.
</details>

<details>
<summary>8. You wrote a NACL inbound rule for port 443 and the connection still fails. Why?</summary>
NACLs are stateless — inbound and outbound are evaluated independently. You must also add an outbound NACL rule allowing the ephemeral ports (1024–65535) so the response can leave the subnet. (A Security Group wouldn't need this — it's stateful.)
</details>

<details>
<summary>9. VPC A peers with B, B peers with C. Can A reach C through B?</summary>
No. VPC peering is non-transitive. You need direct A↔C peering or AWS Transit Gateway for hub-and-spoke at scale.
</details>

## EC2 & Storage

<details>
<summary>1. A T3 instance passes load tests but throttles under sustained real traffic. What's happening?</summary>
T-series are burstable — they spend CPU credits during spikes and throttle when credits run out. Short load tests don't exhaust credits; 30 minutes of sustained traffic does. Fix: move to non-burstable M-series, or enable T-series Unlimited mode (extra CPU beyond baseline is billed — read the implications).
</details>

<details>
<summary>2. "I'll mount the same EBS volume on two EC2 instances for HA." What's wrong with this?</summary>
Only io2 supports multi-attach, and it requires a cluster-aware filesystem (GFS2, OCFS2) to coordinate writes. Plain ext4 on two instances will corrupt the volume.
</details>

<details>
<summary>3. Why is IMDSv1 a security risk?</summary>
IMDSv1 requires no authentication. Server-side code that fetches arbitrary URLs (SSRF) can be tricked into hitting 169.254.169.254 and extracting the instance's IAM credentials. IMDSv2 requires a session token (a PUT before any GET), which blocks this.
</details>

## S3

<details>
<summary>1. Your EC2 instance generates a presigned URL with a 1-hour expiry. It stops working after 15 minutes. What's happening?</summary>
The presigned URL is signed with the credentials of the identity that created it. The EC2 instance uses an IAM role — temporary STS credentials with their own (here ~15 min) lifetime. The URL dies when those credentials expire, regardless of the configured expiry. For long-lived presigned URLs, use an IAM user with long-lived access keys.
</details>

<details>
<summary>2. Is S3 eventually consistent?</summary>
No — S3 has been strongly consistent for all operations since December 2020. Citing eventual consistency as a current concern trips up candidates who memorised old content.
</details>

<details>
<summary>3. Versioning is enabled and your bucket bill keeps growing. Why?</summary>
Every version of every object is retained; a DELETE only adds a delete marker. Old versions accumulate silently. Add lifecycle rules to expire or transition old versions when you enable versioning.
</details>

## Load Balancing & Auto Scaling

<details>
<summary>1. Does ALB preserve the client's original IP address?</summary>
No — the source IP becomes the ALB's IP. Read the real client IP from the X-Forwarded-For header. NLB preserves the source IP natively.
</details>

<details>
<summary>2. Your app on EC2 returns 5xx but the ASG never replaces the instance. Why?</summary>
By default the ASG checks only EC2 instance status, not application health. Enable ALB health check integration on the ASG so instances failing the ALB's checks are replaced too.
</details>

<details>
<summary>3. What's the operational problem with sticky sessions?</summary>
Uneven load distribution — a target holding 60% of long-lived sessions takes 60% of the load regardless of fleet size. Prefer stateless application design with sessions in ElastiCache.
</details>

## RDS & Caching

<details>
<summary>1. Multi-AZ vs Read Replicas — what's the difference?</summary>
Multi-AZ is HA/DR: a synchronous standby in another AZ, automatic DNS failover on primary failure, standby serves no reads. Read Replicas are read scalability: asynchronous replication with lag, replicas serve read traffic, cross-region possible, promotable to standalone.
</details>

<details>
<summary>2. You write to the primary and immediately read from a replica — stale data. Why?</summary>
Read replica replication is asynchronous (ms-to-seconds lag), so replicas are eventually consistent. Read-your-own-writes applications must read from the primary or implement read-after-write consistency logic.
</details>

<details>
<summary>3. How should your application handle RDS Multi-AZ failover?</summary>
Failover takes 60–120 seconds (DNS TTL propagation is part of it). The app reconnects to the same endpoint — use retry with backoff, not a single-attempt connection.
</details>

<details>
<summary>4. Why can Aurora add replicas without impacting the primary, when RDS read replicas can't?</summary>
Aurora replicas share the primary's storage layer — they only track the log position, no data replication. RDS read replicas add replication load on the primary.
</details>

## Observability

<details>
<summary>1. An S3 bucket's permissions were changed last night. How do you find out who did it?</summary>
CloudTrail. It records every API call — who, from where, with what parameters. CloudWatch shows traffic metrics, not the policy-changing API call.
</details>

<details>
<summary>2. Is CloudTrail suitable for real-time security alerting?</summary>
No — events can lag up to 15 minutes. For real-time alerting (root login, IAM changes), deliver CloudTrail events to CloudWatch Logs and set up metric filters + alarms.
</details>

<details>
<summary>3. How long are CloudWatch metrics retained?</summary>
15 months for standard metrics; high-resolution (sub-minute) metrics only 3 hours. Longer retention requires exporting to S3 or a third-party system.
</details>

## Messaging

<details>
<summary>1. A message keeps reappearing in your queue even though your consumer is processing it. Why?</summary>
Processing takes longer than the visibility timeout. The message becomes visible again mid-processing and another consumer picks it up. Fix: increase the visibility timeout to match processing time, or call ChangeMessageVisibility mid-flight to extend the window.
</details>

<details>
<summary>2. Interviewer describes ordered processing (debit before credit). You reach for SQS Standard. Wrong — why?</summary>
Standard queues can deliver out of order. Ordered processing requires FIFO queues, which guarantee ordering within a message group (same group ID = ordered, never concurrent).
</details>

<details>
<summary>3. Source queue has 4-day retention, DLQ has 1-day. What's wrong?</summary>
Messages can expire in the DLQ before you investigate. DLQ retention should exceed the source queue's — standard practice is the 14-day maximum.
</details>

<details>
<summary>4. Can you use SQS as a database of historical messages for replay/query?</summary>
No. Messages are deleted after consumption. If you need query, filter, or replay of historical messages, use Kinesis (up to 365 days retention) or an event store.
</details>

<details>
<summary>5. What happens to an SNS message if the subscriber (HTTP endpoint / Lambda) is unavailable?</summary>
It's lost — SNS does not persist messages. For reliability, always subscribe an SQS queue to the topic so it buffers until the consumer is ready. Direct Lambda subscriptions risk loss if Lambda is throttled.
</details>

<details>
<summary>6. Your Kinesis stream is throttling on one shard while others are idle. Why?</summary>
Hot shard — low-cardinality partition keys (boolean flag, small type list) hash most records onto one shard, which hits its 1 MB/s write limit. Fix: high-cardinality partition keys (user IDs, order IDs, UUIDs).
</details>

<details>
<summary>7. A broken record in a Kinesis stream halts your Lambda consumer. Why didn't it just go to a DLQ like SQS?</summary>
Kinesis event source mapping retries the same batch until success or data expiry — one bad record blocks the whole shard. Fix: BisectBatchOnFunctionError (Lambda splits the failing batch to isolate the bad record) plus an on-failure destination (SQS/SNS).
</details>

## Containers & Serverless

<details>
<summary>1. ECS scales tasks up but they stay PENDING. Why?</summary>
Task-level and instance-level scaling are independent. The desired count rose but the EC2 nodes have no remaining CPU/memory. Fix: cluster capacity scaling (capacity provider / ASG) or move the service to Fargate.
</details>

<details>
<summary>2. You attached S3 read permissions to the EC2 Instance Profile instead of the Task Role. Problem?</summary>
It works, but every task on that node now gets S3 access, not just the one that needs it. Instance Profile is for the ECS Agent (node-level); application permissions belong in the Task Role — least privilege.
</details>

<details>
<summary>3. "EKS scales nodes automatically." True or false?</summary>
False. The control plane is managed, but node scaling requires the Cluster Autoscaler or Karpenter — without them, pods go Pending forever.
</details>

<details>
<summary>4. Can Fargate (ECS or EKS) run DaemonSets?</summary>
No. DaemonSets run one pod per node, and Fargate has no nodes. Log collectors / monitoring agents / security scanners must run on EC2 nodes.
</details>

<details>
<summary>5. One batch Lambda spikes and now every user-facing Lambda in the account is throttled. What happened?</summary>
Lambda concurrency is account-wide (default 1,000). The batch job consumed it all. Fix: Reserved Concurrency on critical functions to guarantee them a budget.
</details>

<details>
<summary>6. "My Lambda works locally but times out in production." First check?</summary>
VPC configuration. A Lambda in a private subnet with no NAT Gateway cannot reach the internet (external APIs) — it times out silently. Same VPC networking model as EC2.
</details>

<details>
<summary>7. Your API Gateway endpoint returns 504 after 29 seconds, but Lambda allows 15 minutes. Why?</summary>
API Gateway has a hard 29-second timeout regardless of Lambda's limit. For long-running operations: enqueue to SQS, return 202 Accepted immediately, and have the client poll for the result.
</details>

<details>
<summary>8. When does ALB become cheaper than API Gateway in front of Lambda?</summary>
Roughly 700 million requests/month. API Gateway charges per request; ALB charges per hour + LCU. Above the break-even, ALB (or containers) wins — a real architectural decision at product companies.
</details>

## Route 53 & CloudFront

<details>
<summary>1. You changed a DNS record and users still hit the old IP. What's the mechanism, and the practice?</summary>
TTL. Resolvers serve the cached record until TTL expires. Practice: lower TTL to 60s, 24–48h before a planned migration, raise it back after the change is stable.
</details>

<details>
<summary>2. You want myapp.com (zone apex) to point to an ALB. CNAME or Alias?</summary>
Alias. A CNAME cannot exist at the zone apex (it can't coexist with the required NS/SOA records). Alias is Route 53-specific, works at apex, resolves AWS resource IPs directly, and queries to AWS resources are free.
</details>

<details>
<summary>3. How do you shift 20% of European traffic from eu-west-1 to eu-central-1 gradually?</summary>
Geoproximity routing with a bias adjustment — bias grows/shrinks a region's catchment area. Geolocation is binary (in a country or not) and can't do gradual shifts.
</details>

<details>
<summary>4. Geolocation routing configured for India and US only. A user in Brazil reports your domain "doesn't exist." Why?</summary>
No default record. Unmatched locations get NXDOMAIN. Always configure a default record in geolocation routing.
</details>

<details>
<summary>5. CloudFront fronts an SSE-KMS (customer-managed key) S3 bucket using OAI. Objects fail to load. Why?</summary>
OAI doesn't support SSE-KMS buckets — the OAI principal lacks KMS decrypt. Use OAC (its replacement), which lets you grant the CloudFront principal KMS permissions.
</details>

<details>
<summary>6. You generated an S3 Presigned URL for content behind CloudFront with OAC. It returns 403. Why?</summary>
OAC makes the bucket reject all direct S3 access, including presigned URLs. Use CloudFront Signed URLs/cookies instead — they operate at the distribution level.
</details>

<details>
<summary>7. Signed URL or signed cookie for a subscriber who should access an entire video library?</summary>
Signed cookie — one cookie grants access to many objects matching a pattern (e.g. videos/* for 24h). Signed URLs are for one specific object. And remember: invalidations cost money past 1,000 paths/month — versioned filenames are the standard alternative.
</details>

## S3 (additions)

<details>
<summary>1. SSE-KMS bucket handling thousands of requests/second starts throwing SlowDown. What's happening?</summary>
KMS API throttling — every object read/write makes a KMS call for the data key. Fix: request a KMS quota increase or enable S3 Bucket Keys (bucket-level data key, up to 99% fewer KMS calls).
</details>

<details>
<summary>2. You enabled replication on a bucket with existing data. Why isn't the old data showing up in the destination?</summary>
Replication only applies to objects written after configuration. Existing objects need S3 Batch Operations to copy. Also: versioning must be on both buckets, and delete markers don't replicate by default.
</details>

<details>
<summary>3. What must every KMS key policy include?</summary>
A statement allowing the account root. Without it (e.g. if the only allowed role is deleted), no one — including root and AWS support — can manage the key. It becomes permanently inaccessible.
</details>

<details>
<summary>4. Does disabling or rotating a KMS key lose data?</summary>
Disabling makes data temporarily undecryptable until re-enabled (scheduled deletion has a mandatory 7–30 day window for this reason). Rotation does NOT re-encrypt existing data — old key material is retained to decrypt old ciphertext; new data uses the new material.
</details>

## Secrets & CI/CD

<details>
<summary>1. Why does Secrets Manager keep the previous version valid during rotation?</summary>
Instances may still hold the old password in connection pools. AWSCURRENT and AWSPREVIOUS must both work until every instance refreshes. Killing the previous version immediately breaks in-flight connections.
</details>

<details>
<summary>2. Where do 200 app configuration parameters belong — Secrets Manager or Parameter Store?</summary>
Parameter Store Standard (free). Secrets Manager at $0.40/secret/month = $80/month for config. Use Secrets Manager only for secrets needing rotation or cross-account sharing.
</details>

<details>
<summary>3. Your app calls GetSecretValue on every DB query. What's wrong?</summary>
~5ms latency and API cost per request. Use the Secrets Manager caching client — in-memory cache, refreshed periodically or on authentication failure (which signals rotation).
</details>

<details>
<summary>4. Blue/green deployment rolled back, but production is still broken. Why?</summary>
CodeDeploy rollback doesn't undo database migrations. The schema change ran before the traffic shift; the old app version must work with the new schema — migrations must be backwards-compatible. The most common blue/green production incident.
</details>

<details>
<summary>5. Your canary completely fails but the alarm (error rate > 1%) never fires. Why?</summary>
A dead 10% canary shows as ~0.1% aggregate error rate — below threshold. Monitor the canary target group's own error rate (per-deployment-group alarms) or lower thresholds during bake periods.
</details>

## Cost

<details>
<summary>1. Your AWS bill spiked 40% this month. Walk me through the investigation.</summary>
1. Cost Explorer: which service, which region.
2. Break down by usage type: compute, storage, data transfer?
3. Break down by resource tag: which team/app?
4. Service-specific checks — EC2: ASG scaled without scale-in / new instance type / Spot→On-Demand fallback. NAT: BytesOutToDestination + Flow Logs → destinations. S3: non-current versions, egress, LIST storms. RDS: new replica, Multi-AZ, storage auto-growth. Data transfer: cross-AZ, cross-region, egress.
</details>

<details>
<summary>2. What's the single most overlooked AWS cost item at product companies?</summary>
NAT Gateway data processing ($0.045/GB on top of hourly cost). Fix: Gateway Endpoints for S3/DynamoDB (free), Interface Endpoints for other AWS services, and audit remaining NAT traffic with Flow Logs.
</details>

<details>
<summary>3. You committed to $10/hour Savings Plans for 3 years and usage dropped. Options?</summary>
None — the commitment is irrevocable; you pay for unused capacity. Lesson: commit only to the guaranteed 24/7 baseline; On-Demand/Spot for everything above.
</details>

<details>
<summary>4. Is traffic between two AZs in the same VPC free?</summary>
No — $0.01/GB each direction. At scale it's significant; co-locate high-volume compute and data in one AZ (accepting the single-AZ availability tradeoff).
</details>

## DynamoDB & Data Services

<details>
<summary>1. Your DynamoDB table is throttled despite sufficient total provisioned capacity. Why?</summary>
Hot partition — a single partition key exceeds 3,000 RCU / 1,000 WCU. Total table capacity doesn't prevent per-partition throttling. Fix: redesign the partition key for high cardinality, or add a random suffix (write sharding) for time-series keys.
</details>

<details>
<summary>2. Your app writes an item then queries the GSI immediately — sometimes it's not there. Why?</summary>
GSI updates are eventually consistent (async propagation from the base table). Read-after-write against a GSI can miss. LSI reads can be strongly consistent; GSI reads cannot.
</details>

<details>
<summary>3. Can you add an LSI to an existing DynamoDB table?</summary>
No — LSIs must be defined at table creation and cannot be added later. New index on existing data = new table + migration. This is why access-pattern analysis happens before table creation.
</details>

<details>
<summary>4. You're hitting the 400KB item limit storing JSON documents in DynamoDB. What's the right model?</summary>
Large payloads belong in S3 with the object key stored as a DynamoDB attribute. Hitting the limit means the data model was never reviewed.
</details>

<details>
<summary>5. "Process 10,000 orders in parallel" — Step Functions?</summary>
No. Step Functions orchestrates a fixed sequence of steps for one execution — it doesn't fan out to competing consumers or buffer events. SQS with multiple consumers is the answer.
</details>

<details>
<summary>6. A mobile app user needs to upload a photo directly to S3. How do you handle auth?</summary>
Both Cognito pieces: User Pool authenticates the user (JWT), Identity Pool exchanges the JWT for temporary STS credentials scoped to an IAM role with S3 write access. The app uploads directly — nothing routes through your backend.
</details>

<details>
<summary>7. You need sub-second data availability in S3 from a Firehose delivery stream. Problem?</summary>
Firehose buffers — minimum 60-second buffer interval before delivery. It's a batch delivery pipeline, not real-time. Sub-second needs Kinesis Data Streams with your own consumer.
</details>

<details>
<summary>8. Your Athena bill is enormous for ad-hoc log queries. First fix?</summary>
Athena charges per TB scanned. An unpartitioned bucket means every query scans everything. Partition by date/service and filter on the partition column in every query.
</details>

<details>
<summary>9. Is OpenSearch a good primary database?</summary>
No — it's a rebuildable secondary index. Without a primary source of truth (RDS/DynamoDB synced via Streams/CDC), you can't replay or recompute the index if it corrupts or when you add fields.
</details>

## Governance & Security

<details>
<summary>1. How do you find out WHO deleted an S3 bucket policy?</summary>
CloudTrail — it records the API call and caller. AWS Config would show the policy is now missing versus its prior state, but not who changed it. Both together give the complete picture.
</details>

<details>
<summary>2. "I'll add a Config rule to prevent public S3 buckets." What's wrong with this?</summary>
Config rules detect non-compliance; they don't prevent anything. Prevention requires SCPs, bucket policies, or S3 Block Public Access. Auto-remediation (SSM) is detection + automatic correction, still not prevention.
</details>

<details>
<summary>3. Does an SCP that allows s3:* grant anyone S3 permissions?</summary>
No. SCPs set the ceiling of maximum available permissions — they never grant. Users still need an explicit IAM allow. This is the most common SCP misunderstanding.
</details>

<details>
<summary>4. Which account is exempt from SCPs, and why does it matter?</summary>
The management account. Anything you want restricted there needs IAM/Config instead — and it's exactly why running workloads in the management account is an anti-pattern: org-wide guardrails can't protect it.
</details>

<details>
<summary>5. GuardDuty vs Inspector vs Macie — pick one for finding compromised EC2 instances?</summary>
Wrong framing — they're complementary. GuardDuty detects active threats (compromise indicators), Inspector scans for vulnerabilities before exploitation, Macie finds sensitive data in S3. Typically all enabled together, aggregated in Security Hub.
</details>

<details>
<summary>6. A DDoS attack scaled your ASG and NAT bill massively. Which service would have covered the cost?</summary>
Shield Advanced (~$3,000/month) — its DDoS cost protection reimburses attack-driven bill spikes, plus the DDoS Response Team. Shield Standard (free) covers only CloudFront/Route 53/ELB L3/L4 attacks, not EC2.
</details>

<details>
<summary>7. Security Hub dashboard in the central account is empty. Most likely cause?</summary>
GuardDuty/Inspector/Macie aren't enabled in the member accounts — Security Hub aggregates their findings but can't create them. Enable the source services everywhere you want visibility.
</details>

<details>
<summary>8. In shared responsibility terms, what do you still own on a fully managed service like Lambda?</summary>
Application code, IAM permissions, data classification and encryption choices, and access policies. AWS owns compute, runtime patching, infrastructure availability. As services get more managed, AWS's share grows — IAM, data, and network access are always yours.
</details>
