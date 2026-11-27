# Reference prices

List prices for **us-east-1** in USD, without free tier, unless the row names
another region. The demo runs in **eu-north-1** (Stockholm, decided in #3); rows
checked for eu-north-1 say so. Other regions are usually 5-20 % higher than
us-east-1. Update a row when you check it again and set the *Checked* date.

Sources:
- **API**: AWS Price List Bulk API,
  `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<service>/current/us-east-1/index.json`
  (public, no credentials needed). Lookups for one service are shown below the table.
- **Unverified**: from general knowledge, not checked against AWS. Verify before
  relying on it.

| Resource | Price | Pricing model | Source | Checked |
|---|---|---|---|---|
| S3 Standard storage | $0.023 per GB-month (first 50 TB) | storage | API `AmazonS3` | 2026-11-27 |
| S3 PUT, COPY, POST, LIST requests | $0.005 per 1,000 | per request | API `AmazonS3` | 2026-11-27 |
| S3 GET and other requests | $0.0004 per 1,000 | per request | API `AmazonS3` | 2026-11-27 |
| S3 Standard storage, eu-north-1 | $0.023 per GB-month (first 50 TB) | storage | API `AmazonS3` (`current/eu-north-1`) | 2026-11-27 |
| S3 PUT / GET requests, eu-north-1 | $0.005 / $0.0004 per 1,000 | per request | API `AmazonS3` (`current/eu-north-1`) | 2026-11-27 |
| AWS Budgets (no budget actions) | $0.00 per budget-day; budget actions $0.10 per budget-day; reports $0.01 each | per day | API `AWSBudgets` | 2026-11-27 |
| IAM roles and policies, IAM OIDC provider, STS | no charge | - | Unverified | - |
| Data transfer out to the internet | $0.09 per GB (first 10 TB, after the 100 GB/month global free tier) | per GB | API `AWSDataTransfer` | 2026-11-27 |
| KMS customer-managed key | $1 per key version per month | per month, always on | API `awskms` | 2026-11-27 |
| KMS asymmetric requests (sign, not RSA 2048) | $0.15 per 10,000 | per request | API `awskms` | 2026-11-27 |
| Public IPv4 address (in use or idle) | $0.005 per hour (~$3.65/month) | per hour | API `AmazonVPC` | 2026-11-27 |
| CloudWatch Logs ingestion | $0.50 per GB | per GB | API `AmazonCloudWatch` | 2026-11-27 |
| IoT Core connectivity | $0.08 per million connection-minutes (~$0.0035 per device-month) | per minute | API `AWSIoT` | 2026-11-27 |
| IoT Core messaging | $1.00 per million messages (first 1 billion) | per message | API `AWSIoT` | 2026-11-27 |
| IoT Device Shadow / Registry operations | $1.25 per million | per operation | API `AWSIoT` | 2026-11-27 |
| IoT Jobs (remote action) | $0.003 per job execution (first 250,000/month) | per request | API `IoTDeviceManagement` | 2026-11-27 |
| EC2 c6i.4xlarge (16 vCPU, 32 GiB) | ~$0.68/h on-demand; spot usually ~$0.25-0.35/h | on-demand / spot, per second | Unverified | - |
| EC2 t3.medium (small host, e.g. hawkBit) | ~$0.042/h on-demand | on-demand, per second | Unverified | - |
| EBS gp3 volume | ~$0.08 per GB-month | storage, billed while it exists | Unverified | - |
| NAT gateway | ~$0.045/h (~$33/month) + $0.045 per GB processed | per hour, always on | Unverified | - |
| Secrets Manager secret | ~$0.40 per secret per month | per month, always on | Unverified | - |

Spot prices change continuously. With AWS credentials:
`aws ec2 describe-spot-price-history --instance-types c6i.4xlarge --product-descriptions Linux/UNIX --max-items 5`.

## Looking up a price in the Bulk API

Download the service file to the scratchpad, then search the price dimensions:

```sh
curl -sS -o <scratchpad>/AmazonS3.json \
  https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/us-east-1/index.json
python3 -I -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
for terms in d["terms"]["OnDemand"].values():
    for t in terms.values():
        for dim in t["priceDimensions"].values():
            if re.search(sys.argv[2], dim["description"], re.I):
                print(dim["pricePerUnit"]["USD"], dim["description"])
' <scratchpad>/AmazonS3.json 'first 50 TB'
```

The `AmazonEC2` file is several GB. Do not download it; use the AWS pricing
pages or `aws pricing get-products` (needs credentials) for EC2, EBS and NAT.
