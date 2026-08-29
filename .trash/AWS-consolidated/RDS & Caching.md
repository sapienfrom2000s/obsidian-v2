# RDS & Caching

## Multi-AZ vs Read Replicas (the most reliably asked RDS question)

Different features, different problems — candidates conflate them.

**Multi-AZ = high availability / DR (disaster recovery).** Synchronous standby in a different AZ — every write confirmed only after landing on the standby. On primary failure, RDS promotes the standby and updates the DNS endpoint; the app reconnects to the same endpoint. No manual intervention. The standby **cannot serve reads** in standard Multi-AZ. Failover: 60–120 seconds.

**Read Replicas = read scalability.** Asynchronous replication (lag: ms to seconds). Serve read traffic to offload the primary. Same AZ, cross-AZ, or cross-region (also a DR option). Can be manually promoted to standalone (breaks replication).

```
Multi-AZ (HA):                       Read Replica (Scale):

Primary DB ──sync──▶ Standby DB      Primary DB ──async──▶ Replica 1
     │                    │                │         ──async──▶ Replica 2
     └── same endpoint ───┘                │         ──async──▶ Replica 3
         (DNS failover)                    │
                                      App reads from replicas
                                      App writes to primary
```

## Aurora

AWS's cloud-native RDBMS, MySQL/PostgreSQL compatible. Separates **storage from compute**: storage replicates 6 ways across 3 AZs automatically. Failover typically **under 30s** (vs 60–120s for RDS Multi-AZ).

Aurora replicas **share the primary's storage** — no data replication needed, just log-position tracking. Adding replicas is fast, minimal lag, and no performance hit on the primary (unlike RDS read replicas, which add replication load).

**Aurora Global Database** — one primary region + read-only secondary regions, replication lag under a second. Global low-latency reads and cross-region DR with RPO < 1s (RPO = recovery point objective: how much data you can afford to lose).

## RDS Proxy

Sits between app and DB, **pools connections**. Solves: databases have finite connections; hundreds of Lambdas/containers each opening connections exhaust the limit. Proxy multiplexes hundreds of app connections onto a few real DB connections.

Bonus: during failover it holds connection requests and reconnects afterward — failover is nearly invisible to the app.

## ElastiCache — Redis vs Memcached

Rule of thumb: unless you have a specific reason for Memcached, **use Redis**.

| | Redis | Memcached |
|---|---|---|
| Persistence | Yes | No |
| Replication | Yes | No |
| Extras | Pub/sub, sorted sets, transactions | Pure LRU (least-recently-used) cache |
| Architecture | Single-threaded | Multithreaded (raw throughput) |

Memcached only for max-throughput simple key-value where durability doesn't matter.

## Caching patterns

**Cache-aside (lazy loading)** — check cache; on miss, read DB, populate cache, return. Cache only holds requested-once data. Stale data accumulates if TTL too long or invalidation is missed.

**Write-through** — every DB write also writes the cache. Cache always fresh; costs write latency (two writes) and fills the cache with data that may never be read.

```
Cache-aside:

App → Cache: GET user:123
Cache → App: MISS
App → DB: SELECT * FROM users WHERE id=123
DB → App: {id: 123, name: "Priya"}
App → Cache: SET user:123 {...} EX 300    ← 300s TTL
App → Client: return user data
```
