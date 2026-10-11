/** Aggregated AWS Cost Explorer data only. No full AWS account IDs. */
export type InfraAwsMonth = {
  month:string; usd:number; accounts:number; services:number; estimated:boolean;
};
export type InfraAwsService = { month:string; service:string; usd:number };
export type InfraAwsAccount = { month:string; label:string; usd:number };
export type InfraPreviewData = {
  mode:"audited-preview-snapshot";
  awsAsOf:string;
  awsRun:{
    finishedAt:string;months:number;accounts:number;rows:number;
    referenceUsd:number;storedDetailUsd:number;driftUsd:number;
  };
  awsMonths:InfraAwsMonth[];
  awsServices:InfraAwsService[];
  awsAccounts:InfraAwsAccount[];
};
