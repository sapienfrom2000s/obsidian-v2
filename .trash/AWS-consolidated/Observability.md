# Observability — CloudWatch vs CloudTrail

## The distinction

- **CloudWatch** — "What is my infrastructure doing right now?" Metrics, logs, alarms, dashboards. The operational monitoring layer.
- **CloudTrail** — "Who did what in my AWS account?" Records every API call: who, from where, with what parameters, when. The audit/compliance layer.

Trap question: "An S3 bucket's permissions were changed last night — how do you find out who did it?" → **CloudTrail**. CloudWatch shows traffic changes, not the API call that modified the bucket policy.

## CloudWatch metrics

AWS services publish automatically: EC2 → CPU, network in/out, disk I/O. RDS → connections, read/write IOPS, replication lag. Custom metrics can be published from apps.

**Consistently asked caveat**: EC2 does **not** publish memory utilisation or disk space usage by default — those live inside the OS and require the **CloudWatch Agent**.

Retention: 15 months for standard metrics; high-resolution (sub-minute) only 3 hours. Longer retention → export to S3 or a third party.

## CloudWatch Logs

Ship via Agent or SDK. Organised into **Log Groups** (one per app/service) and **Log Streams** (one per instance/container). **Log Insights** queries logs with SQL-like syntax.

## CloudWatch alarms

Watch a metric over a window; states OK / ALARM / INSUFFICIENT_DATA. On ALARM: SNS notification, ASG scaling policy, or EC2 action.

```yaml
CPUAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: high-cpu-api-service
    MetricName: CPUUtilization
    Namespace: AWS/EC2
    Statistic: Average
    Period: 60                    # Evaluate every 60s
    EvaluationPeriods: 3          # Breach for 3 consecutive periods
    Threshold: 80
    ComparisonOperator: GreaterThanThreshold
    AlarmActions:
      - !Ref ScalingPolicy
```

## CloudTrail

Logs every management API call (resource creation/deletion, IAM changes) as an event, stored in S3. Console retention is 90 days by default; for longer retention and querying, deliver to S3 (+ optionally CloudWatch Logs).

**Not real-time** — up to 15 minutes of delay. For real-time alerting on sensitive actions (root login, IAM changes), send events to CloudWatch Logs and build metric filters + alarms.
