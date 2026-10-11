/** Aggregated only. No company identifiers or full AWS account IDs in the preview. */
export type InfraAwsMonth = { month:string; usd:number; accounts:number; services:number; estimated:boolean };
export type InfraAwsService = { month:string; service:string; usd:number };
export type InfraAwsAccount = { month:string; label:string; usd:number };
export type InfraBillMonth = { month:string; docs:number; companies:number; measured:number; incomplete:number; total:number; extraction:number; enrichment:number; avg_measured:number|null };
export type InfraDocType = { month:string; doc_type:string; docs:number; total:number; avg_measured:number|null };
export type InfraBillDay = { day:string; docs:number; total:number; incomplete:number };
export type InfraPreviewData = {
  mode:"audited-preview-snapshot";
  awsAsOf:string; billAsOf:string;
  awsRun:{finishedAt:string;months:number;accounts:number;rows:number;referenceUsd:number;storedDetailUsd:number;driftUsd:number};
  awsMonths:InfraAwsMonth[]; awsServices:InfraAwsService[]; awsAccounts:InfraAwsAccount[];
  billMonths:InfraBillMonth[]; docTypes:InfraDocType[]; billDays:InfraBillDay[];
};
