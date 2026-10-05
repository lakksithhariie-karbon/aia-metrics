export interface RetentionKpiActivation {
  integrated: number;
  trained: number;
  post_training_core: number;
  activated: number;
  rate_pct: number | null;
}

export interface RetentionKpiTtv {
  companies: number;
  avg_hours: number | null;
  median_hours: number | null;
}

export interface RetentionKpiChurn {
  month: string | null;
  eligible: number;
  churned: number;
  rate_pct: number | null;
}

export interface RetentionKpiResponse {
  activation: RetentionKpiActivation;
  ttv: RetentionKpiTtv;
  churn: RetentionKpiChurn;
  source_watermark_at: string | null;
  refreshed_at: string | null;
}

export type RetentionHeatmapInterval = "weekly" | "monthly";

export interface RetentionHeatmapRow {
  cohort_start: string;
  cohort_size: number;
  values: Array<number | null>;
}

export interface RetentionHeatmapResponse {
  interval: RetentionHeatmapInterval;
  columns: number;
  rows: RetentionHeatmapRow[];
  source_watermark_at: string | null;
  refreshed_at: string | null;
}
