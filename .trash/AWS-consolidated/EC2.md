# EC2 — Elastic Compute Cloud

## Instance types

Naming: `[family][generation].[size]` — e.g. `c6i.xlarge` = Compute-optimised, 6th gen, Intel, xlarge.

| Family            | Series | Use case                                             |
| ----------------- | ------ | ---------------------------------------------------- |
| General Purpose   | T / M  | Balanced workloads                                   |
| Compute Optimised | C      | Batch, game servers, transcoding                     |
| Memory Optimised  | R      | In-memory DBs, large caches                          |
| Storage Optimised | I      | High-IOPS (I/O ops/sec) DBs, distributed filesystems |

**T-series is burstable**: accumulate CPU credits while idle, spend them on spikes. Credits exhausted → throttled. Production trap: a T3 fine in a 10-minute load test can throttle under 30 minutes of sustained real traffic.

## Purchasing options

- **On-Demand** — pay per second, no commitment. Unpredictable workloads.
- **Reserved Instances** — 1 or 3-year commit to a specific type/region, up to 72% cheaper. Trap: locked to that instance type (Convertible RIs trade flexibility for less discount).
- **Savings Plans** — commit to $/hour spend. Discount applies across families and even Lambda/Fargate. Compute Savings Plans most flexible; EC2 Instance Savings Plans deeper discount per family.
- **Spot** — up to 90% cheaper; AWS reclaims with a **2-minute warning**. App must drain connections, checkpoint state, complete in-flight work. Batch jobs, data processing, stateless tiers behind an ASG (Auto Scaling Group).
- **Capacity Reservations** — guarantee capacity in a specific AZ. No discount, just availability. Pre-spike (sales events).
- **Dedicated Hosts** — entire physical server. Per-socket/per-core licensing or single-tenant compliance.

## User data and instance metadata

**User Data** — bootstrap script, runs once at first boot as root, before the app:

```bash
#!/bin/bash
yum update -y                                        # Patch OS on first boot
aws s3 cp s3://my-bucket/config /etc/app/config      # Pull config from S3
systemctl enable --now my-app                        # Start the application
```

**Instance Metadata** at `http://169.254.169.254/latest/meta-data/` — instance ID, AZ, type, IAM role credentials. No auth on **IMDSv1** → SSRF (server-side request forgery — tricking server code into fetching attacker-chosen URLs) can extract credentials. **IMDSv2** requires a session token (PUT before GET) — current best practice.

## Storage: EBS, EFS, Instance Store

```
Decision tree:
Shared access across many instances?        → EFS
Highest single-instance IOPS (database)?    → io2 EBS
Simple persistent disk for one instance?    → gp3 EBS
Temporary scratch, speed is everything?     → Instance Store
```

**Instance Store** — physically attached to the host. Fastest, but ephemeral: lost on stop/terminate/failure. Scratch space, temp files, rebuildable caches only.

**EBS (Elastic Block Store)** — network-attached drive, persists independently of the instance.

| Type | Notes |
|---|---|
| `gp3` | General SSD; baseline 3000 IOPS independent of size, scale to 16k IOPS; default and usually cheapest |
| `gp2` | Older; IOPS scale with size (3 IOPS/GB, burst to 3000) |
| `io2` | Provisioned IOPS for sub-ms DB latency; **only type supporting multi-attach** |
| `sc1` | Cold HDD, infrequent access, lowest cost |

**Multi-attach caveat**: one io2 volume on multiple EC2s requires a cluster-aware filesystem (GFS2, OCFS2). Plain ext4 will corrupt data.

**EFS (Elastic File System)** — managed NFS (Network File System), mountable by thousands of instances, multi-AZ, scales automatically. Pricier than EBS per GB; essential for shared files (shared config, ML weights, CMS assets).

## Placement groups

- **Cluster** — same rack, one AZ. 10Gbps+ inter-instance bandwidth, lowest latency; rack failure kills everything. HPC (high-performance computing), distributed DBs.
- **Spread** — distinct hardware per instance, max 7 per AZ. Small groups of critical instances avoiding correlated failure.
- **Partition** — logical partitions on separate hardware. Large distributed systems (HDFS, HBase, Cassandra) wanting rack-awareness.
