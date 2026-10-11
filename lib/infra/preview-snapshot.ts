import type { InfraPreviewData } from "./types";

/**
 * Read-only audited AWS Cost Explorer aggregates, captured 8 Oct 2026.
 * INFRA PREVIEW ONLY, NOT A LIVE API.
 * No raw account IDs, credentials, Jira records or document-processing data.
 * The source is monthly UnblendedCost in USD, including taxes and Savings Plans.
 * Current-month AWS values are incomplete estimates.
 * Before production, replace this frozen preview with an audited access-controlled reader.
 */
export const infraPreviewData:InfraPreviewData = {
  "mode": "audited-preview-snapshot",
  "awsAsOf": "2026-10-08T04:17:14.429071Z",
  "awsRun": {
    "finishedAt": "2026-10-08T04:17:14.464108Z",
    "months": 14,
    "accounts": 16,
    "rows": 11966,
    "referenceUsd": 42964.75,
    "storedDetailUsd": 42964.7313,
    "driftUsd": 0
  },
  "awsMonths": [
    {
      "month": "2026-01",
      "usd": 2413.23,
      "accounts": 9,
      "services": 31,
      "estimated": false
    },
    {
      "month": "2026-02",
      "usd": 2647.26,
      "accounts": 9,
      "services": 31,
      "estimated": false
    },
    {
      "month": "2026-03",
      "usd": 2785.81,
      "accounts": 12,
      "services": 30,
      "estimated": false
    },
    {
      "month": "2026-04",
      "usd": 3372.2,
      "accounts": 14,
      "services": 30,
      "estimated": false
    },
    {
      "month": "2026-05",
      "usd": 3477.66,
      "accounts": 14,
      "services": 29,
      "estimated": false
    },
    {
      "month": "2026-06",
      "usd": 3815.41,
      "accounts": 14,
      "services": 33,
      "estimated": false
    },
    {
      "month": "2026-07",
      "usd": 4999.89,
      "accounts": 14,
      "services": 33,
      "estimated": false
    },
    {
      "month": "2026-08",
      "usd": 4301.14,
      "accounts": 14,
      "services": 32,
      "estimated": false
    },
    {
      "month": "2026-09",
      "usd": 4016.56,
      "accounts": 14,
      "services": 33,
      "estimated": false
    },
    {
      "month": "2026-10",
      "usd": 1400.94,
      "accounts": 16,
      "services": 34,
      "estimated": true
    }
  ],
  "awsServices": [
    {
      "month": "2026-05",
      "service": "Amazon Relational Database Service",
      "usd": 983.84
    },
    {
      "month": "2026-05",
      "service": "Tax",
      "usd": 530.46
    },
    {
      "month": "2026-05",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 520.8
    },
    {
      "month": "2026-05",
      "service": "Amazon Elastic Container Service",
      "usd": 338.34
    },
    {
      "month": "2026-05",
      "service": "EC2 - Other",
      "usd": 321.8
    },
    {
      "month": "2026-05",
      "service": "AmazonCloudWatch",
      "usd": 233.93
    },
    {
      "month": "2026-05",
      "service": "Amazon Elastic Load Balancing",
      "usd": 142.42
    },
    {
      "month": "2026-05",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 140.11
    },
    {
      "month": "2026-05",
      "service": "Amazon Virtual Private Cloud",
      "usd": 63.38
    },
    {
      "month": "2026-05",
      "service": "AWS Cost Explorer",
      "usd": 47.01
    },
    {
      "month": "2026-05",
      "service": "AWS WAF",
      "usd": 39.23
    },
    {
      "month": "2026-06",
      "service": "Amazon Relational Database Service",
      "usd": 1067.18
    },
    {
      "month": "2026-06",
      "service": "Tax",
      "usd": 581.98
    },
    {
      "month": "2026-06",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 504
    },
    {
      "month": "2026-06",
      "service": "Amazon Elastic Container Service",
      "usd": 453.44
    },
    {
      "month": "2026-06",
      "service": "EC2 - Other",
      "usd": 331.95
    },
    {
      "month": "2026-06",
      "service": "AmazonCloudWatch",
      "usd": 278.12
    },
    {
      "month": "2026-06",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 161.55
    },
    {
      "month": "2026-06",
      "service": "Amazon Elastic Load Balancing",
      "usd": 140.69
    },
    {
      "month": "2026-06",
      "service": "Amazon Virtual Private Cloud",
      "usd": 66.35
    },
    {
      "month": "2026-06",
      "service": "AWS Cost Explorer",
      "usd": 50.98
    },
    {
      "month": "2026-06",
      "service": "AWS WAF",
      "usd": 48.62
    },
    {
      "month": "2026-07",
      "service": "Amazon Elastic Container Service",
      "usd": 1188.8
    },
    {
      "month": "2026-07",
      "service": "Amazon Relational Database Service",
      "usd": 1143.35
    },
    {
      "month": "2026-07",
      "service": "Tax",
      "usd": 762.64
    },
    {
      "month": "2026-07",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 520.8
    },
    {
      "month": "2026-07",
      "service": "AmazonCloudWatch",
      "usd": 337.95
    },
    {
      "month": "2026-07",
      "service": "EC2 - Other",
      "usd": 337.43
    },
    {
      "month": "2026-07",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 158.95
    },
    {
      "month": "2026-07",
      "service": "Amazon Elastic Load Balancing",
      "usd": 137.57
    },
    {
      "month": "2026-07",
      "service": "Amazon ElastiCache",
      "usd": 77.29
    },
    {
      "month": "2026-07",
      "service": "Amazon Virtual Private Cloud",
      "usd": 70.8
    },
    {
      "month": "2026-07",
      "service": "AWS WAF",
      "usd": 60.93
    },
    {
      "month": "2026-08",
      "service": "Amazon Relational Database Service",
      "usd": 1202.83
    },
    {
      "month": "2026-08",
      "service": "Tax",
      "usd": 656.07
    },
    {
      "month": "2026-08",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 520.8
    },
    {
      "month": "2026-08",
      "service": "EC2 - Other",
      "usd": 465.6
    },
    {
      "month": "2026-08",
      "service": "Amazon Elastic Container Service",
      "usd": 456.61
    },
    {
      "month": "2026-08",
      "service": "AmazonCloudWatch",
      "usd": 257.55
    },
    {
      "month": "2026-08",
      "service": "Amazon Elastic Load Balancing",
      "usd": 137.62
    },
    {
      "month": "2026-08",
      "service": "Amazon ElastiCache",
      "usd": 105.65
    },
    {
      "month": "2026-08",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 79.95
    },
    {
      "month": "2026-08",
      "service": "Amazon Virtual Private Cloud",
      "usd": 75.86
    },
    {
      "month": "2026-08",
      "service": "AWS WAF",
      "usd": 66.19
    },
    {
      "month": "2026-09",
      "service": "Amazon Relational Database Service",
      "usd": 1166.96
    },
    {
      "month": "2026-09",
      "service": "Tax",
      "usd": 612.7
    },
    {
      "month": "2026-09",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 504
    },
    {
      "month": "2026-09",
      "service": "EC2 - Other",
      "usd": 460.7
    },
    {
      "month": "2026-09",
      "service": "Amazon Elastic Container Service",
      "usd": 299.71
    },
    {
      "month": "2026-09",
      "service": "AmazonCloudWatch",
      "usd": 220.82
    },
    {
      "month": "2026-09",
      "service": "Amazon Elastic Load Balancing",
      "usd": 132.95
    },
    {
      "month": "2026-09",
      "service": "Amazon ElastiCache",
      "usd": 102.24
    },
    {
      "month": "2026-09",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 77.37
    },
    {
      "month": "2026-09",
      "service": "Amazon Virtual Private Cloud",
      "usd": 76.86
    },
    {
      "month": "2026-09",
      "service": "AWS WAF",
      "usd": 69.61
    },
    {
      "month": "2026-10",
      "service": "Savings Plans for AWS Compute usage",
      "usd": 520.8
    },
    {
      "month": "2026-10",
      "service": "Amazon Relational Database Service",
      "usd": 294.38
    },
    {
      "month": "2026-10",
      "service": "Tax",
      "usd": 213.7
    },
    {
      "month": "2026-10",
      "service": "EC2 - Other",
      "usd": 128.44
    },
    {
      "month": "2026-10",
      "service": "Amazon Elastic Container Service",
      "usd": 53.16
    },
    {
      "month": "2026-10",
      "service": "AmazonCloudWatch",
      "usd": 37.27
    },
    {
      "month": "2026-10",
      "service": "Amazon Elastic Load Balancing",
      "usd": 26.89
    },
    {
      "month": "2026-10",
      "service": "Amazon ElastiCache",
      "usd": 22.62
    },
    {
      "month": "2026-10",
      "service": "Amazon Virtual Private Cloud",
      "usd": 17.86
    },
    {
      "month": "2026-10",
      "service": "Amazon EC2 Container Registry (ECR)",
      "usd": 17.13
    },
    {
      "month": "2026-10",
      "service": "Amazon Simple Storage Service",
      "usd": 16.52
    }
  ],
  "awsAccounts": [
    {
      "month": "2026-05",
      "label": "Account 03",
      "usd": 1632.95
    },
    {
      "month": "2026-05",
      "label": "Account 10",
      "usd": 617.15
    },
    {
      "month": "2026-05",
      "label": "Account 04",
      "usd": 472.4
    },
    {
      "month": "2026-05",
      "label": "Account 01",
      "usd": 88.32
    },
    {
      "month": "2026-05",
      "label": "Account 07",
      "usd": 88.32
    },
    {
      "month": "2026-05",
      "label": "Account 09",
      "usd": 88.32
    },
    {
      "month": "2026-05",
      "label": "Account 11",
      "usd": 88.32
    },
    {
      "month": "2026-05",
      "label": "Account 12",
      "usd": 88.32
    },
    {
      "month": "2026-05",
      "label": "Account 14",
      "usd": 88.32
    },
    {
      "month": "2026-06",
      "label": "Account 03",
      "usd": 1833.53
    },
    {
      "month": "2026-06",
      "label": "Account 10",
      "usd": 701.93
    },
    {
      "month": "2026-06",
      "label": "Account 04",
      "usd": 540.07
    },
    {
      "month": "2026-06",
      "label": "Account 01",
      "usd": 85.44
    },
    {
      "month": "2026-06",
      "label": "Account 11",
      "usd": 85.44
    },
    {
      "month": "2026-06",
      "label": "Account 12",
      "usd": 85.44
    },
    {
      "month": "2026-06",
      "label": "Account 14",
      "usd": 85.44
    },
    {
      "month": "2026-06",
      "label": "Account 07",
      "usd": 85.44
    },
    {
      "month": "2026-06",
      "label": "Account 09",
      "usd": 85.44
    },
    {
      "month": "2026-07",
      "label": "Account 03",
      "usd": 2983.9
    },
    {
      "month": "2026-07",
      "label": "Account 10",
      "usd": 734.55
    },
    {
      "month": "2026-07",
      "label": "Account 04",
      "usd": 523.56
    },
    {
      "month": "2026-07",
      "label": "Account 11",
      "usd": 88.25
    },
    {
      "month": "2026-07",
      "label": "Account 12",
      "usd": 88.25
    },
    {
      "month": "2026-07",
      "label": "Account 01",
      "usd": 88.25
    },
    {
      "month": "2026-07",
      "label": "Account 07",
      "usd": 88.25
    },
    {
      "month": "2026-07",
      "label": "Account 09",
      "usd": 88.25
    },
    {
      "month": "2026-07",
      "label": "Account 14",
      "usd": 88.25
    },
    {
      "month": "2026-08",
      "label": "Account 03",
      "usd": 2239.93
    },
    {
      "month": "2026-08",
      "label": "Account 10",
      "usd": 774.86
    },
    {
      "month": "2026-08",
      "label": "Account 04",
      "usd": 527.72
    },
    {
      "month": "2026-08",
      "label": "Account 07",
      "usd": 88.26
    },
    {
      "month": "2026-08",
      "label": "Account 09",
      "usd": 88.26
    },
    {
      "month": "2026-08",
      "label": "Account 15",
      "usd": 88.26
    },
    {
      "month": "2026-08",
      "label": "Account 01",
      "usd": 88.25
    },
    {
      "month": "2026-08",
      "label": "Account 11",
      "usd": 88.25
    },
    {
      "month": "2026-08",
      "label": "Account 12",
      "usd": 88.25
    },
    {
      "month": "2026-09",
      "label": "Account 03",
      "usd": 2146.19
    },
    {
      "month": "2026-09",
      "label": "Account 10",
      "usd": 706.76
    },
    {
      "month": "2026-09",
      "label": "Account 04",
      "usd": 430.56
    },
    {
      "month": "2026-09",
      "label": "Account 11",
      "usd": 85.44
    },
    {
      "month": "2026-09",
      "label": "Account 01",
      "usd": 85.43
    },
    {
      "month": "2026-09",
      "label": "Account 14",
      "usd": 85.43
    },
    {
      "month": "2026-09",
      "label": "Account 12",
      "usd": 85.42
    },
    {
      "month": "2026-09",
      "label": "Account 07",
      "usd": 85.42
    },
    {
      "month": "2026-09",
      "label": "Account 09",
      "usd": 85.42
    },
    {
      "month": "2026-10",
      "label": "Account 03",
      "usd": 412.06
    },
    {
      "month": "2026-10",
      "label": "Account 04",
      "usd": 164.36
    },
    {
      "month": "2026-10",
      "label": "Account 10",
      "usd": 115.67
    },
    {
      "month": "2026-10",
      "label": "Account 07",
      "usd": 87.88
    },
    {
      "month": "2026-10",
      "label": "Account 09",
      "usd": 87.88
    },
    {
      "month": "2026-10",
      "label": "Account 01",
      "usd": 87.87
    },
    {
      "month": "2026-10",
      "label": "Account 11",
      "usd": 87.87
    },
    {
      "month": "2026-10",
      "label": "Account 12",
      "usd": 87.87
    },
    {
      "month": "2026-10",
      "label": "Account 14",
      "usd": 87.87
    }
  ]
};
