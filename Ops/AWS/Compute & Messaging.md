# Compute & Messaging

Decoupled communication (SQS, SNS, Kinesis) and the ways workloads run (ECS, EKS, Lambda, API Gateway).

## Messaging — SQS, SNS, Kinesis

### The one idea behind all of it

One app sends a message. Another app receives it. That's it — **publish** = send, **consume** = receive.

```
App A ──"order placed"──► [ middle thing ] ──► App B
        publishes                        consumes
```

Why bother with the middle thing at all? App A doesn't need to know who cares about "order placed", where they live, or whether they're awake. It drops the message and moves on. The middle thing holds it and hands it over when the receiver is ready.

Every service in this note is the same picture with one change: what the middle thing does with the message —
- **SQS**: hand it to one receiver, then throw it away
- **SNS**: give a copy to everyone who asked
- **Kinesis**: let everyone read it, and keep it around so they can read again later
- **Amazon MQ**: whatever your old apps already expect

### SQS — Simple Queue Service

#### Mental model

Durable, distributed queue: producer writes → consumer polls, processes, deletes. Until explicit `DeleteMessage`, the message stays. This makes SQS **at-least-once delivery** — duplicates happen, so **consumers must be idempotent** (processing a message twice must produce the same result as once).

- **Standard** — unlimited throughput, no ordering guarantee, possible duplicates.
- **FIFO** — strict ordering within a **message group** (same group ID → ordered, never concurrent); 300 msg/s cap (3,000 batched). Exactly-once via **deduplication ID** (duplicates within 5 min discarded). Use only when ordering genuinely matters.

```mermaid
flowchart TB
    subgraph SP["Producers"]
        S1["Web app"]
        S2["Mobile app"]
        S3["Batch job"]
    end

    S1 -->|"m5, m2, m9<br/>(no order, any mix)"| SQ
    S2 -->|"m3, m3 duplicate"| SQ
    S3 -->|"m8, m1"| SQ

    subgraph SQ["Standard Queue — unlimited throughput"]
        direction LR
        M2["m2"] --- M5["m5"] --- M9["m9"] --- M3["m3 dup!"] --- M1["m1"] --- M8["m8"]
    end

    SQ -->|"any message, any consumer"| SC1["Consumer 1<br/>gets m5"]
    SQ -->|"any message, any consumer"| SC2["Consumer 2<br/>gets m2 + m3 dup"]
    SQ -->|"any message, any consumer"| SC3["Consumer 3<br/>gets m9"]

    subgraph FP["Producers"]
        PA["Order service<br/>GroupID: order-A"]
        PB["Payment service<br/>GroupID: payment-42"]
        PC["Shipment service<br/>GroupID: order-B"]
    end

    PA -->|"m1, m2, m3<br/>(same GroupID → same lane)"| G1
    PB -->|"m1, m2"| G2
    PC -->|"m1, m2, m3"| G3

    subgraph FQ["FIFO Queue — ordered per group, 300 msg/s"]
        direction TB
        subgraph G1["Group: order-A"]
            direction LR
            A1["m1"] --> A2["m2"] --> A3["m3"]
        end
        subgraph G2["Group: payment-42"]
            direction LR
            B1["m1"] --> B2["m2"]
        end
        subgraph G3["Group: order-B"]
            direction LR
            C1["m1"] --> C2["m2"] --> C3["m3"]
        end
    end

    G1 -->|"sequential only"| CA["Consumer A"]
    G2 -->|"parallel with other groups"| CB["Consumer B"]
    G3 -->|"parallel with other groups"| CC["Consumer C"]

    CA -.->|"in-flight blocks m2, m3<br/>of group order-A"| G1
```

**How to read it — top half (Standard)**: messages land in a single unordered pool. Any consumer gets any message; the pool may contain **duplicates** (`m3` sent twice → possibly processed twice — hence idempotent consumers) and no ordering (`m5` arrives before `m2`). Throughput is unlimited.

**Bottom half (FIFO)**: each GroupID is an independent ordered lane. Consumer A processing `m1` of `order-A` blocks `m2`/`m3` **of that group only** — meanwhile `payment-42` and `order-B` flow freely to other consumers. Ordering where it matters, parallelism everywhere else. Deduplication IDs silently discard duplicate sends within 5 minutes.

#### Visibility timeout — the most important operational detail

On poll, the message isn't deleted — it's made **invisible for the visibility timeout** (default 30s). Consumer must process + delete in that window. Crash or timeout → message becomes visible again, another consumer picks it up.

**Trap**: processing consistently longer than the timeout → duplicate processing. Fix: raise the timeout to match processing time, or call `ChangeMessageVisibility` mid-flight to extend.

#### Long vs short polling

Short polling returns immediately (billed even when empty). Long polling waits up to 20s for a message — reduces empty responses, cost, CPU spin. Almost always right: set `WaitTimeSeconds` 1–20.

#### Dead Letter Queue (DLQ)

After a message fails processing `maxReceiveCount` times (each visibility-timeout expiry increments the count), SQS moves it to the DLQ automatically.

Without a DLQ, **poison pills** (messages that always fail — malformed payload, bug, dead dependency) loop forever, burning consumer capacity. With one, they're quarantined for inspection, alerting, and replay. DLQ retention should be long (14 days max).

```
Poison pill with DLQ (maxReceiveCount=3):
Queue → Consumer (fails, count=1) → (fails, 2) → (fails, 3)
      → SQS moves message to DLQ → Alert fires → Engineer investigates
```

#### SQS + ASG scaling pattern

Scale consumers on **queue depth** (`ApproximateNumberOfMessagesVisible`), not CPU. Queue depth is a **leading indicator** — the fleet grows before consumers are overwhelmed.

```mermaid
graph LR
    P[Producers] --> Q[SQS Queue]
    Q --> CW["CloudWatch<br/>queue depth"]
    CW -->|"depth > 1000: add 2"| ASG[ASG]
    ASG --> C1["Consumer 1"]
    ASG --> C2["Consumer 2"]
    C1 -->|poll + delete| Q
    C2 -->|poll + delete| Q
```

### SNS — Simple Notification Service

#### Pub/sub model

Producer publishes one message to a **topic**; SNS pushes to all subscribers simultaneously (SQS, Lambda, HTTP, email, SMS). Key difference from SQS: **SQS is pull-based, SNS is push-based**, and SNS does **not persist** — an unavailable subscriber loses the message unless it's an SQS queue (which buffers).

#### Fan-out pattern — SNS + SQS

One event → multiple independent downstream systems, each with its own queue and processing rate. Slow analytics service? Its queue backs up; inventory and notifications unaffected. Adding a fourth consumer = new SQS subscriber, zero producer changes.

```mermaid
graph LR
    P[Publisher] --> T["SNS Topic:<br/>order.placed"]
    T --> Q1[SQS inventory]
    T --> Q2[SQS notifications]
    T --> Q3[SQS analytics]
    Q1 --> C1[Inventory Consumer]
    Q2 --> C2[Notification Consumer]
    Q3 --> C3[Analytics Consumer]
```

#### Message filtering

Each subscriber defines a **filter policy** (JSON on message attributes); SNS delivers only matching messages. Filtering lives at the **subscription**, not the publisher — one topic with filter policies beats one topic per message type.

```json
{ "order_type": ["physical"] }
```

### Kinesis Data Streams

#### When is it actually used?

**SQS is a to-do list. Kinesis is a diary.**

- SQS messages are **tasks** — "process this order." Done once, deleted, worthless afterwards.
- Kinesis records are **facts** — "user clicked X at 14:03." Facts don't get "done." Different teams ask different questions about the same facts, at different times.

Reach for Kinesis when:

1. **Multiple consumers need the same data** — fraud team, dashboard, and warehouse all reading one clickstream. (SQS gives each message to exactly one consumer.)
2. **You want to re-ask questions later** — new ML model? Re-train on last month. Bug in the pipeline? Replay. (SQS deletes history on consume.)
3. **It's a continuous flow, not discrete tasks** — clicks, logs, IoT sensors, trades: events/second, forever. An order to process is a *queue* problem; a firehose of events is a *stream* problem.
4. **Real-time reaction is the product** — fraud alerts within seconds, not hourly batch.

#### Core model

Real-time streaming: a **stream** is divided into **shards**; each shard = 1 MB/s write, 2 MB/s read. Producers assign a **partition key**; Kinesis hashes it to pick the shard. Same key → same shard, strictly ordered within the shard.

**Replay is the defining feature SQS lacks**: retention 24h default, up to 365 days. Records can be re-read.

```mermaid
flowchart TB
    PA["Producer<br/>key: user-123"] --> S1
    PB["Producer<br/>key: user-456"] --> S2

    subgraph K["Kinesis Stream"]
        direction LR
        subgraph S1["Shard 1"]
            direction LR
            R1["click"] --- R2["click"] --- R3["purchase"]
        end
        subgraph S2["Shard 2"]
            direction LR
            R4["click"] --- R5["click"] --- R6["click"]
        end
    end

    S1 --> C1["Consumer 1"]
    S1 --> C2["Consumer 2"]
    S2 --> C1
    S2 --> C2
```

Three ideas:

1. **Same key → same shard** → records with the same key stay ordered.
2. **Shards run in parallel**; each is capped at 1 MB/s in, 2 MB/s out.
3. **All consumers read the same records** — nothing is deleted, so any consumer can rewind and replay (24h–365d retention).

**Replay example**: the warehouse loader writes to S3 via Firehose. At 14:00 the warehouse goes down for an hour; the loader can't write, but **the stream doesn't care** — records keep flowing in and just sit there. At 15:00 the warehouse recovers. The loader rewinds its checkpoint to the 14:00 position and re-reads that hour — no data lost, producers never knew anything happened. With SQS, every message delivered during the outage would have been deleted after processing (or lost in the dead consumer) — there's nothing to go back to.

#### Kinesis vs SQS — decision framework

```
                    SQS                         Kinesis Data Streams
─────────────────────────────────────────────────────────────────────
Ordering           No (Standard),               Yes, per shard
                   Yes (FIFO, limited)
Delivery           At-least-once                At-least-once
Consumers          One message, one consumer    Multiple consumers, same data
Replay             No — deleted after consume   Yes — up to 365 days
Throughput         No provisioning              Shard = 1MB/s in, 2MB/s out
Retention          4–14 days                    24h–365 days
Message size       256 KB                       1 MB
Use case           Task queues, async decoupling  Real-time analytics, event
                                               sourcing, log aggregation
```

**Heuristic**: multiple independent consumers reading the same data, or replay needed → Kinesis. Distribute work where each message is done once → SQS.

Scenario test: "clickstream events; data science dashboard + fraud scoring + warehouse load" — three consumers, same data, real-time → **Kinesis**. "Process each order exactly once" → **SQS**.

### Kinesis Data Firehose

Fully managed **delivery pipeline**: ingests a stream, buffers, optionally transforms via Lambda, delivers to S3 / Redshift / OpenSearch / Splunk. No consumers, shards, or checkpoints to manage. Pay per data volume ingested.

```mermaid
flowchart LR
    P["Producers<br/>(apps, SDK, agents)"] --> FH

    subgraph FH["Firehose (fully managed)"]
        direction LR
        B["buffer"] --> T["optional Lambda<br/>transform"] --> F["batch"]
    end

    FH -->|"click, click, purchase,<br/>click... (60s–900s of data)"| S3["S3 bucket<br/>events/2026/08/25/"]
```

Three ideas:

1. **No consumers to build** — you don't read from Firehose; AWS delivers *for* you. Your app just pushes events in.
2. **It buffers and batches** — events arrive continuously, but delivery waits for a buffer window (60s–900s) or size. Latency is minutes, not milliseconds.
3. **Destination is storage** — S3, Redshift, OpenSearch. The data lands *at rest*, ready for SQL/queries — not in a running app.

The batch node in the diagram shows what actually gets delivered: one file containing a chunk of the stream (e.g. all events from a 60s window), written into a dated S3 prefix.

|           | Data Streams                 | Firehose                      |
| --------- | ---------------------------- | ----------------------------- |
| Purpose   | Real-time stream processing  | Delivery to storage/analytics |
| Consumers | You build them (Lambda, KCL) | AWS manages delivery          |
| Latency   | <200ms                       | Buffer interval 60s–900s      |
| Replay    | Yes (365d)                   | No                            |
| Scaling   | Manual / on-demand           | Automatic                     |

Often used together: Streams feed Lambda for real-time AND Firehose for archival.

```
Clickstream → Kinesis Stream ─┬→ Lambda fraud scoring  (real-time, seconds)
                              └→ Firehose → S3          (archival, minutes)
```

### Amazon MQ

Managed version of ActiveMQ / RabbitMQ. Exists for one reason: you have an **old app already built around one of these tools**, and it's moving to AWS. Instead of rewriting the app to use SQS/SNS, point it at Amazon MQ — nothing else changes.

```mermaid
flowchart LR
    subgraph YOUR_DC["Your data center"]
        ERP["ERP system<br/>(old, can't rewrite)"]
        CRM["CRM<br/>(old, can't rewrite)"]
        LEG["Legacy Java app<br/>(can't rewrite)"]
    end

    subgraph AWS["Amazon MQ"]
        MQ["Message broker"]
    end

    ERP -->|"order created"| MQ
    LEG -->|"invoice paid"| MQ
    MQ -->|"order →"| CRM
    MQ -->|"invoice →"| ERP
```

Usage: old systems that already speak a messaging protocol talk to each other through Amazon MQ — the ERP drops "order created" onto it, the CRM picks it up, the legacy app publishes "invoice paid", the ERP consumes it. Nobody rewrites anything; each app just points at Amazon MQ instead of the old server. **You'd never pick this for a new project** — new projects use SQS/SNS.

Three ideas:

1. **Nothing about your app changes** — it keeps using the same messaging tools it always did. You only change the address it connects to: your server → AWS's server.
2. **A server you don't fully control** — AWS runs it, patches it, keeps it alive across failures. But it's still a server somewhere with a size you pick. SQS/SNS have no server at all — you just call an API.
3. **Don't choose it for new apps** — it exists purely as the easy path for old apps. A new app should use SQS/SNS: simpler, cheaper, nothing to run.

The dashed border on Amazon MQ = "there's a server in the middle again." With SQS/SNS that box doesn't exist — apps talk directly to AWS's messaging API and AWS handles everything behind it.

```
Choosing a messaging service:
New app on AWS?                    → SQS (queues) / SNS (pub/sub)
Fan-out to multiple consumers?     → SNS + SQS
Existing JMS/AMQP/MQTT app?        → Amazon MQ (migration path)
Real-time stream processing?       → Kinesis Data Streams
Deliver stream to S3/Redshift?     → Kinesis Firehose
```

## Containers & Serverless — ECS, EKS, Lambda, API Gateway

### ECS — Elastic Container Service

#### Mental model

- **Task Definition** — blueprint: image, CPU/memory, ports, env vars, IAM role, volumes.
- **Task** — a running instance of the definition.
- **Service** — maintains desired task count, integrates with LBs, replaces failures.
- **Cluster** — the compute they run on.

```mermaid
flowchart LR
    TD["Task Definition<br/>(blueprint)"] -->|"run 3 of these"| SVC["Service<br/>keeps 3 alive"]
    SVC --> T1["Task 1"]
    SVC --> T2["Task 2"]
    SVC --> T3["Task 3"]
    T1 & T2 & T3 --> CL["Cluster<br/>(the machines)"]
    LB["Load Balancer"] --> T1 & T2 & T3
    SVC -.->|"Task 2 dies<br/>→ start a new one"| T2
```

Read it as: the blueprint says *what* to run, the service says *how many*, the cluster is *where*. Task 2 dies → the service notices and starts a replacement. That self-healing is the service's whole job.

#### Launch types: EC2 vs Fargate

**Launch type = whose machines your containers run on.** The container itself is identical either way — same image, same definition. The only thing it decides: when the task runs, is the hardware underneath yours or Amazon's?

- **EC2 launch type** — *your* machines. Your EC2 instances, your patching, your sizing; ECS just places containers on them. Cheaper at scale, more control.
- **Fargate launch type** — *Amazon's* machines. You hand ECS a container and say "run this"; compute appears, runs it, disappears. You never see a server. More expensive per compute unit, zero machine ops.

```mermaid
flowchart TB
    subgraph EC2["EC2 launch type — you run the machines"]
        direction LR
        N1["Node<br/>(you patch, you size)"] --> T1["Task"]
        N1 --> T2["Task"]
        N2["Node<br/>(you patch, you size)"] --> T3["Task"]
    end
    subgraph FG["Fargate launch type — AWS runs the machines"]
        direction LR
        T4["Task"] --- T5["Task"] --- T6["Task"]
    end
```

#### The two IAM roles (consistently confused)

- **EC2 Instance Profile** — attached to the *node*; used by the **ECS Agent** (register with control plane, pull definitions, ship logs).
- **ECS Task Role** — in the task definition; assumed by the **application in the container** (S3 reads, DynamoDB writes).

Attaching app permissions to the Instance Profile "works" but gives *every* task on the node that access — least privilege means Task Roles.

```
EC2 Node
  └── Instance Profile (ECS Agent perms)
Container (Task)
  └── Task Role (application perms)
```

#### Deployment strategies

- **Rolling** — replace old tasks in batches (`minimumHealthyPercent` / `maximumPercent`). Risk: some traffic hits a broken version before rollback.
- **Blue/Green (CodeDeploy)** — new version runs alongside old; traffic shifted all-at-once, canary, or linear; automatic rollback to blue on failed health checks. Safer for production.

Blue/Green is the **setup**: old and new both running, side by side. Canary/linear/all-at-once are the **shift speed** — how fast you move traffic from old to new within that setup:

```
Blue/Green setup (both running):
                    ┌─ Blue (v1) ◄── traffic
  users ──► LB ─────┤
                    └─ Green (v2) ◄── waiting

Shift speed choices:
  all-at-once:  blue 100% → green 100%          (instant flip)
  canary:       blue 95% / green 5% → 25% → 100% (ramp, small blast radius)
  linear:       blue 90% / green 10% → 20% → 100% (even steps over an hour)
```

They're often mixed up because "canary deploy" is also a name for the whole approach — the difference is just whether the second environment exists (blue/green always has one; canary-only doesn't need a full idle copy).

#### ECS auto scaling

Service Auto Scaling adjusts **desired task count** (Target Tracking / Step / Scheduled; metrics like `ECSServiceAverageCPUUtilization`, ALB `RequestCountPerTarget`).

Critical: **task scaling ≠ instance scaling**. Tasks scale up but nodes are full → tasks stuck PENDING. EC2 launch type needs both ECS Service Auto Scaling and cluster capacity scaling. Fargate removes the problem.

### EKS — Elastic Kubernetes Service

#### Control plane vs data plane (always asked)

- **Control plane** (AWS-managed): API server, scheduler, controller manager, etcd (the cluster's state database) — replicated across AZs, ~$0.10/hr. You never see these nodes.
- **Data plane** (you manage): worker nodes — EC2 node groups or Fargate.

```mermaid
graph TD
    subgraph CP["AWS Managed — Control Plane"]
        API[kube-apiserver]
        ETCD[etcd]
    end
    subgraph DP["Your Account — Data Plane"]
        NG[Managed Node Groups]
        FG[Fargate]
    end
    kubectl --> API
    API --> NG
    API --> FG
```

#### Node types

- **Managed Node Groups** — EKS provisions and lifecycle-manages EC2 nodes (AMI updates, drain before terminate). Most common.
- **Self-Managed Nodes** — you manage AMIs/patching; for configs managed groups don't support.
- **Fargate** — each pod in isolated compute. **No DaemonSets** (no nodes), no local-storage stateful workloads. Bursty/stateless only.

#### AWS Load Balancer Controller

Watches Kubernetes Ingress resources and **provisions an ALB** — translates Ingress paths into ALB listener rules and target groups. The standard way to expose EKS services.

#### EKS node autoscaling

EKS does **not** scale nodes automatically — pods go Pending until you scale manually or run the **Cluster Autoscaler** (or Karpenter). "EKS scales automatically" is the classic wrong answer: the control plane is managed, node scaling is not.

#### ECS vs EKS

| | ECS | EKS |
|---|---|---|
| Complexity | Low, AWS-native | High, full K8s curve |
| Portability | AWS-only | Runs anywhere K8s runs |
| Ecosystem | AWS integrations | Vast CNCF (Prometheus, Istio, Argo) |
| Use when | AWS-only, simpler workloads | Multi-cloud, K8s expertise, service mesh |

### Lambda

#### Invocation models (the most important Lambda concept)

| | Sync | Async | Event Source Mapping |
|---|---|---|---|
| Callers | API Gateway, ALB, SDK | S3 events, SNS, EventBridge | Lambda polls SQS/Kinesis/DynamoDB Streams |
| Behaviour | Caller waits for response | Fire-and-forget | Batches delivered to function |
| Retries | **None** — caller retries | Auto: 2 retries w/ backoff → DLQ/Destination | SQS: batch returns to queue; Kinesis: **retries same batch until success — a bad record blocks the whole shard** |

```mermaid
flowchart TB
    subgraph SYNC["Sync — caller waits"]
        AG["API Gateway"] -->|"HTTP request<br/>…waits for response…"| L1["Lambda"]
        L1 -->|"response"| AG
    end
    subgraph ASYNC["Async — fire and forget"]
        S3["S3 upload"] -->|"event"| L2["Lambda"]
        S3 -.->|"moves on immediately"| S3
    end
    subgraph ESM["Event Source Mapping — Lambda pulls"]
        SQS["SQS queue"] -->|"Lambda polls,<br/>batch of 10"| L3["Lambda"]
        L3 -->|"ok → delete"| SQS
        L3 -->|"fail → back to queue"| SQS
    end
```

Three shapes, one service. Sync: someone's waiting on the other end. Async: event fired, nobody waits. Event source mapping: **Lambda is the puller** — the queue does nothing but sit there, and Lambda decides when to come take messages.

#### Cold starts

No warm environment → provision compute, init runtime, run init code: 100ms–1s extra. Worse with: big packages, Java, (historically) VPC.

**The correct programming model**: everything outside the handler runs once per cold start and is reused by warm invocations — SDK clients, DB connection pools, config.

```python
import boto3

s3_client = boto3.client('s3')          # runs ONCE per cold start
db = create_db_connection()             # expensive — outside handler

def handler(event, context):            # runs per invocation
    return s3_client.get_object(Bucket='my-bucket', Key=event['key'])
```

**Provisioned Concurrency** — pre-initialised environments, always warm; pay continuously. For latency-sensitive user-facing functions.

#### Lambda in a VPC

Default Lambda can't reach VPC resources. Configure VPC/subnets/SG → Lambda creates ENIs. The historical ENI-per-cold-start penalty was fixed in 2019 (shared, pre-created ENIs) — still asked to test you know the evolution.

**VPC Lambda + internet**: private subnet without a NAT Gateway = no internet, same as EC2. "Works locally, times out in production" → check VPC/subnet/NAT.

#### Lambda + SQS event source mapping

Lambda polls, batches, invokes; deletes on success, returns to queue on failure.

```yaml
BatchSize: 10
MaximumBatchingWindowInSeconds: 5
FunctionResponseTypes:
  - ReportBatchItemFailures    # only FAILED messages return to queue
```

`ReportBatchItemFailures` matters: without it, 1 failed message in a batch of 10 retries all 10 — 9 processed twice.

#### Concurrency

Account-wide pool (default 1,000). One function can starve the rest → set **Reserved Concurrency** on critical functions.

### API Gateway

#### What it does

Managed front door: routing, auth (IAM, Cognito, Lambda authorizers), rate limiting/usage plans, SSL termination, request/response transformation, monitoring. Standard entry point for Lambda APIs (ALB and function URLs lack built-in auth/throttling).

#### Integrations

- **Lambda Proxy** — full HTTP request as a structured event; most common.
- **HTTP** — managed reverse proxy to ALB/EC2/any HTTP endpoint.
- **AWS Service** — call AWS directly, no Lambda: `POST /orders` → SQS enqueue.

#### API Gateway vs ALB

| | API Gateway | ALB |
|---|---|---|
| Auth | Built-in (IAM, Cognito, authorizers) | None built-in |
| Rate limiting | Usage plans, per-client throttling | None |
| Request transform | Yes | No |
| Cost | Per request | Per hour + LCU |
| Latency overhead | ~10–50ms | Minimal |

**Cost trap**: per-request pricing gets expensive at volume — break-even vs ALB ≈ 700M requests/month.

**Hard timeout**: 29 seconds — API Gateway 504s even though Lambda allows 15 minutes. Long ops → async pattern: enqueue to SQS, return 202, client polls.

```mermaid
flowchart LR
    C["Client"] -->|"POST /report<br/>(takes 5 min)"| AG["API Gateway"]
    AG -->|"invoke"| L["Lambda"]
    L -->|"enqueue job"| SQS["SQS"]
    L -->|"202 Accepted<br/>job-id, instantly"| AG
    AG --> C
    SQS --> W["Worker<br/>(does the 5 min)"]
    C -.->|"GET /report/job-id<br/>poll until done"| AG
```

The trick: the API call itself returns in milliseconds; the slow work happens behind the queue. The client polls for the result instead of holding the connection open — because API Gateway hangs up at 29 seconds no matter what Lambda is allowed to do.
