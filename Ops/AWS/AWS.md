# AWS

Notes from [AWS Fundamentals: IAM, VPC, EC2 & Core Services](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-02-25-aws-fundamentals-iam-vpc-ec2-core-services.md) and the follow-up posts ([messaging & containers](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-03-01-aws-messaging-containers-sqs-sns-kinesis-ecs-eks-lambda.md), [networking & content delivery](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-03-01-aws-networking-content-delivery-route53-cloudfront.md), [data services](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-03-04-aws-data-services-dynamodb-step-functions-cognito.md), [governance & security](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-03-04-aws-governance-security-config-organizations-vpc.md), [operations](https://github.com/sapienfrom2000s/notes/blob/main/_posts/2026-03-28-aws-operations-kms-secrets-cicd-cost-optimization.md)).

## Notes

1. [[Ops/AWS/Foundations|Foundations]] — IAM (identity, policies, roles, STS), VPC (subnets, routing, IGW/NAT, SG vs NACLs, endpoints, peering, Transit Gateway), EC2 (instance types, purchasing options, EBS/EFS/Instance Store, placement groups), S3 (storage classes, versioning, lifecycle, policies, presigned URLs, replication, encryption), Load Balancing & Auto Scaling (ALB/NLB/GLB, target groups, ASG scaling policies)
2. [[Ops/AWS/Networking & Content Delivery|Networking & Content Delivery]] — Route 53 (DNS resolution, TTL, routing policies, health checks), Global Accelerator (anycast IPs), CloudFront (edge caching, OAC, cache behaviours, signed URLs/cookies, invalidation)
3. [[Ops/AWS/Compute & Messaging|Compute & Messaging]] — SQS, SNS, fan-out, Kinesis Streams vs Firehose, Amazon MQ; ECS, EKS, Lambda invocation models, API Gateway
4. [[Ops/AWS/Data Services|Data Services]] — RDS (Multi-AZ vs read replicas, Aurora, RDS Proxy, ElastiCache), DynamoDB (partition keys, GSI/LSI, DAX, streams, global tables), Step Functions & Cognito (state machines, Standard vs Express, User Pools vs Identity Pools), database selection framework (Athena vs Redshift)
5. [[Ops/AWS/Security & Operations|Security & Operations]] — KMS (envelope encryption, key policies), Secrets Manager vs Parameter Store, Config, Organizations/SCPs, WAF/Shield/GuardDuty, shared responsibility, CloudWatch vs CloudTrail, cost optimisation (EC2/RDS/S3 levers, NAT Gateway, bill-spike investigation)

## Interview Prep

- [[Ops/AWS/Questions/SRE|SRE Questions]] — scenario questions and gotchas across all topics
- [[Ops/AWS/Questions/General|General Questions]] — networking, architecture (full web-app answer, CAP, DR/HA Postgres), security-per-layer, cost/IaC, behavioral
