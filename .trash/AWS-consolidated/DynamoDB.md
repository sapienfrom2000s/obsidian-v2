# DynamoDB

Serverless key-value/document DB, single-digit ms at any scale. The mental shift: **design the data model around your access patterns upfront** — no query planner, no ad-hoc joins later.

## Data model

- **Primary key** = partition key alone, or partition + sort key.
- **Partition key** — hashed to pick the physical partition; same key = same partition, ordered by sort key.
- **Sort key** — orders items within a partition, enables range queries ("orders for user X in last 30 days"). Without it: exact-match lookups only.
- **Schemaless** items, but **400KB max item size** — large payloads go to S3 with a reference in DynamoDB.

## Partition key design — the most important concept

Each partition: 3,000 RCU / 1,000 WCU (read/write capacity units — defined in the capacity section below). Too much traffic on one partition key = **hot partition** = throttling even when total table capacity is fine.

```
Bad:  PK = "status" (PENDING/COMPLETE)  → 90% of traffic hits one partition
      PK = date at day granularity      → today's writes pile onto one partition
Good: PK = userId, orderId, UUID        → even distribution
      Time-series you must partition by time → write sharding (random suffix,
      fan-out reads across shards)
```

## GSI vs LSI

| | LSI | GSI |
|---|---|---|
| Keys | **Same partition key**, different sort key | Completely different partition (+sort) key |
| When created | **At table creation only — cannot add later** | Any time |
| Scope | Single partition queries only | Any access pattern |
| Throughput | Shares the base table's | Own independent provisioned capacity |
| Consistency | Can be strongly consistent | **Eventually consistent** — read-after-write may miss |

Example: base table `PK=orderId` can't answer "all orders for customer C" → add GSI `PK=customerId, SK=timestamp`.

## Consistency & capacity

- **Eventually consistent reads** (default): cheaper. **Strongly consistent**: 2x RCU, higher latency — only where stale reads break correctness (inventory, balances).
- **Provisioned mode**: specify RCU/WCU (1 RCU = 1 strong read/s ≤4KB; 1 WCU = 1 write/s ≤1KB); cheaper for steady load; pair with Auto Scaling.
- **On-demand**: pay per request, no planning, no throttling on spikes — new/unknown/variable workloads.
- **Transactions**: up to 100 items across tables, 2x cost — don't use where atomicity isn't needed.

## DAX

In-memory cache purpose-built for DynamoDB: microsecond reads, **write-through**, zero application code changes (vs ElastiCache's cache-aside logic). Only works with DynamoDB.

## Streams — change data capture

Time-ordered item-level modifications, retained 24h. Canonical pattern: stream record → Lambda → update OpenSearch index / invalidate ElastiCache / notify / replicate. DynamoDB's equivalent of a WAL.

## Global Tables

Multi-region **multi-master** replication — any region accepts writes; last-writer-wins conflict resolution; sub-second lag. Active-active global architectures with local read/write latency.
