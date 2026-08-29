# CloudFront

## Edge caching model

CDN with 450+ edge locations. User → nearest edge: cache hit = served immediately (origin never touched); miss = edge fetches from origin (S3, ALB, EC2, any HTTP server), caches, serves. Effect: lower latency + drastically reduced origin load.

## Origin Access Control (OAC) — locking S3 to CloudFront

Problem: a public S3 origin can be bypassed directly. **OAC** makes the bucket private and grants read only to the CloudFront service principal — all access must flow through CloudFront.

```
Without OAC:  User → S3 directly ✓  (bypass — bad)
With OAC:     User → S3 directly ✗  (403); only CloudFront → S3 works
```

OAC replaces the older OAI; unlike OAI it supports SSE-KMS buckets and all regions.

## Cache behaviours

One distribution, multiple behaviours by URL path pattern → different origins/settings:

```
Path Pattern    Origin          TTL
/api/*       →  ALB (dynamic)   0s       never cache
/static/*    →  S3              86400s   24h
/images/*    →  S3              604800s  7 days
/* (default) →  ALB             0s
```

Path matching is **longest-prefix wins**, not first-match.

## Signed URLs vs Signed Cookies

Both restrict CloudFront content to authorised users:

- **Signed URL** — access to one specific object. Purchased file, single download.
- **Signed cookie** — access to many objects matching a pattern. Subscriber gets all of `videos/*` for 24h via one cookie.

vs **S3 Presigned URLs**: those grant *direct S3* access. With OAC configured, direct S3 access is blocked — S3 presigned URLs return 403; you must use CloudFront signed URLs/cookies.

## Cache invalidation

Origin updated but edges serve the old version until TTL expiry. Invalidation forces edges to drop cached paths — free for the first 1,000 paths/month, then billed.

**Production pattern**: versioned filenames (`main.v2.js`) instead of invalidations — new file = natural cache miss; old expires on its own. Invalidating `/*` every deploy is a classic cost mistake.

## Geo-restriction

Whitelist/blacklist countries at the edge — blocked countries get 403 without touching the origin. Content licensing and export compliance.
