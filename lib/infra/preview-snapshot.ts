import type { InfraPreviewData } from "./types";

/**
 * Read-only, audited aggregate capture. Preview shell ONLY, not a live cost API.
 * AWS Cost Explorer aws_costs captured 2026-10-08; bill_costs captured 2026-10-11.
 * No AWS account IDs, company names, prediction UUIDs or credentials.
 * Replace with a properly authenticated database facade before production.
 *
 * NOTE: AWS is USD UnblendedCost, including Tax/Savings Plans. Bill-processing
 * cost-unit currency is not established; never display it as USD by assumption.
 * Current-month AWS Cost Explorer values are estimated and incomplete.
 */
export const infraPreviewData:InfraPreviewData = {
  "mode": "audited-preview-snapshot",
  "awsAsOf": "2026-10-08T04:17:14.429071Z",
  "billAsOf": "2026-10-11T12:30:52.648723Z",
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
  ],
  "billMonths": [
    {
      "month": "2026-08",
      "docs": 10683,
      "companies": 243,
      "measured": 8323,
      "incomplete": 2360,
      "total": 256.33,
      "extraction": 211.85,
      "enrichment": 44.48,
      "avg_measured": 0.03075
    },
    {
      "month": "2026-09",
      "docs": 14201,
      "companies": 352,
      "measured": 14181,
      "incomplete": 20,
      "total": 487.03,
      "extraction": 429.02,
      "enrichment": 58.01,
      "avg_measured": 0.03429
    },
    {
      "month": "2026-10",
      "docs": 3747,
      "companies": 163,
      "measured": 3747,
      "incomplete": 0,
      "total": 163.71,
      "extraction": 156.27,
      "enrichment": 7.44,
      "avg_measured": 0.04369
    }
  ],
  "docTypes": [
    {
      "month": "2026-08",
      "doc_type": "scanned",
      "docs": 5644,
      "total": 174.65,
      "avg_measured": 0.03909
    },
    {
      "month": "2026-08",
      "doc_type": "digital",
      "docs": 4434,
      "total": 58.31,
      "avg_measured": 0.01696
    },
    {
      "month": "2026-08",
      "doc_type": "handwritten",
      "docs": 589,
      "total": 22.7,
      "avg_measured": 0.0547
    },
    {
      "month": "2026-08",
      "doc_type": "Unclassified",
      "docs": 16,
      "total": 0.67,
      "avg_measured": 0.04192
    },
    {
      "month": "2026-09",
      "doc_type": "scanned",
      "docs": 9006,
      "total": 359.8,
      "avg_measured": 0.03996
    },
    {
      "month": "2026-09",
      "doc_type": "digital",
      "docs": 4550,
      "total": 94.83,
      "avg_measured": 0.02084
    },
    {
      "month": "2026-09",
      "doc_type": "handwritten",
      "docs": 631,
      "total": 31.76,
      "avg_measured": 0.05033
    },
    {
      "month": "2026-09",
      "doc_type": "Unclassified",
      "docs": 14,
      "total": 0.64,
      "avg_measured": 0.04572
    },
    {
      "month": "2026-10",
      "doc_type": "scanned",
      "docs": 2766,
      "total": 130.77,
      "avg_measured": 0.04728
    },
    {
      "month": "2026-10",
      "doc_type": "digital",
      "docs": 838,
      "total": 26.29,
      "avg_measured": 0.03138
    },
    {
      "month": "2026-10",
      "doc_type": "handwritten",
      "docs": 142,
      "total": 6.64,
      "avg_measured": 0.04677
    },
    {
      "month": "2026-10",
      "doc_type": "Unclassified",
      "docs": 1,
      "total": 0,
      "avg_measured": 0.00429
    }
  ],
  "billDays": [
    {
      "day": "2026-09-01",
      "docs": 490,
      "total": 15.3,
      "incomplete": 2
    },
    {
      "day": "2026-09-02",
      "docs": 560,
      "total": 15.84,
      "incomplete": 0
    },
    {
      "day": "2026-09-03",
      "docs": 618,
      "total": 21.14,
      "incomplete": 2
    },
    {
      "day": "2026-09-04",
      "docs": 881,
      "total": 20.29,
      "incomplete": 0
    },
    {
      "day": "2026-09-05",
      "docs": 565,
      "total": 10.35,
      "incomplete": 0
    },
    {
      "day": "2026-09-06",
      "docs": 101,
      "total": 3.35,
      "incomplete": 0
    },
    {
      "day": "2026-09-07",
      "docs": 345,
      "total": 11.59,
      "incomplete": 3
    },
    {
      "day": "2026-09-08",
      "docs": 1052,
      "total": 27.9,
      "incomplete": 0
    },
    {
      "day": "2026-09-09",
      "docs": 708,
      "total": 25.38,
      "incomplete": 0
    },
    {
      "day": "2026-09-10",
      "docs": 660,
      "total": 19.39,
      "incomplete": 0
    },
    {
      "day": "2026-09-11",
      "docs": 536,
      "total": 16.02,
      "incomplete": 1
    },
    {
      "day": "2026-09-12",
      "docs": 381,
      "total": 13.42,
      "incomplete": 0
    },
    {
      "day": "2026-09-13",
      "docs": 401,
      "total": 10.12,
      "incomplete": 0
    },
    {
      "day": "2026-09-14",
      "docs": 212,
      "total": 8.65,
      "incomplete": 1
    },
    {
      "day": "2026-09-15",
      "docs": 109,
      "total": 3.89,
      "incomplete": 0
    },
    {
      "day": "2026-09-16",
      "docs": 287,
      "total": 9.7,
      "incomplete": 0
    },
    {
      "day": "2026-09-17",
      "docs": 623,
      "total": 17.83,
      "incomplete": 0
    },
    {
      "day": "2026-09-18",
      "docs": 227,
      "total": 7.76,
      "incomplete": 0
    },
    {
      "day": "2026-09-19",
      "docs": 511,
      "total": 20.47,
      "incomplete": 3
    },
    {
      "day": "2026-09-20",
      "docs": 407,
      "total": 12.49,
      "incomplete": 7
    },
    {
      "day": "2026-09-21",
      "docs": 319,
      "total": 13.27,
      "incomplete": 0
    },
    {
      "day": "2026-09-22",
      "docs": 539,
      "total": 21.82,
      "incomplete": 0
    },
    {
      "day": "2026-09-23",
      "docs": 469,
      "total": 20.67,
      "incomplete": 0
    },
    {
      "day": "2026-09-24",
      "docs": 499,
      "total": 25.53,
      "incomplete": 0
    },
    {
      "day": "2026-09-25",
      "docs": 460,
      "total": 17.55,
      "incomplete": 0
    },
    {
      "day": "2026-09-26",
      "docs": 281,
      "total": 11.04,
      "incomplete": 0
    },
    {
      "day": "2026-09-27",
      "docs": 75,
      "total": 3.17,
      "incomplete": 0
    },
    {
      "day": "2026-09-28",
      "docs": 505,
      "total": 20.55,
      "incomplete": 0
    },
    {
      "day": "2026-09-29",
      "docs": 708,
      "total": 32.66,
      "incomplete": 0
    },
    {
      "day": "2026-09-30",
      "docs": 672,
      "total": 29.86,
      "incomplete": 1
    },
    {
      "day": "2026-10-01",
      "docs": 454,
      "total": 20.3,
      "incomplete": 0
    },
    {
      "day": "2026-10-02",
      "docs": 183,
      "total": 7.26,
      "incomplete": 0
    },
    {
      "day": "2026-10-03",
      "docs": 355,
      "total": 15.56,
      "incomplete": 0
    },
    {
      "day": "2026-10-04",
      "docs": 11,
      "total": 0.42,
      "incomplete": 0
    },
    {
      "day": "2026-10-05",
      "docs": 410,
      "total": 16.31,
      "incomplete": 0
    },
    {
      "day": "2026-10-06",
      "docs": 486,
      "total": 21.11,
      "incomplete": 0
    },
    {
      "day": "2026-10-07",
      "docs": 480,
      "total": 21.65,
      "incomplete": 0
    },
    {
      "day": "2026-10-08",
      "docs": 616,
      "total": 29.54,
      "incomplete": 0
    },
    {
      "day": "2026-10-09",
      "docs": 463,
      "total": 20.56,
      "incomplete": 0
    },
    {
      "day": "2026-10-10",
      "docs": 229,
      "total": 8.16,
      "incomplete": 0
    },
    {
      "day": "2026-10-11",
      "docs": 60,
      "total": 2.83,
      "incomplete": 0
    }
  ]
};
