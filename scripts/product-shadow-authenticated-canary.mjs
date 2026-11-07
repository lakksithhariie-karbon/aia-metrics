// Authorized one-shot Edge ingestion smoke test. Run only inside a secured
// runtime with existing Supabase service JWT and CRON_SECRET. Never log secrets.
// No GitHub Actions or cron schedule is added by this file.
const required = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required managed env: ${name}`);
  return value;
};
if (process.env.PRODUCT_SHADOW_CANARY_APPROVED !== 'yes') {
  throw new Error('Set PRODUCT_SHADOW_CANARY_APPROVED=yes after reviewing the test plan');
}
const url = new URL(required('SUPABASE_URL'));
if (url.protocol !== 'https:' || url.hostname !== 'hdgbmcerogqfocyxdnpw.supabase.co') {
  throw new Error('Refusing to call a Supabase project other than the verified Product project');
}
const jwt = required('SUPABASE_SERVICE_ROLE_KEY');
const cronSecret = required('CRON_SECRET');
const parts = jwt.split('.');
if (parts.length !== 3) throw new Error('Service credential must be a legacy service_role JWT');
let claims;
try {
  claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
} catch {
  throw new Error('Cannot parse JWT claims');
}
if (claims.role !== 'service_role') throw new Error('Refusing token without service_role claim');
const base = url.origin;
const headers = {
  apikey: jwt,
  Authorization: `Bearer ${jwt}`,
  'Content-Type': 'application/json',
};
async function publicWatermark() {
  const response = await fetch(
    `${base}/rest/v1/export_watermarks?job_name=eq.incremental&select=last_success_at,last_success_date,status`,
    { headers, signal: AbortSignal.timeout(15000) },
  );
  if (!response.ok) throw new Error(`Could not read live watermark: HTTP ${response.status}`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw new Error('Expected exactly one live incremental watermark');
  }
  return rows[0];
}
async function shadowWatermark() {
  const response = await fetch(`${base}/rest/v1/rpc/shadow_product_watermark`, {
    method: 'POST', headers, body: '{}', signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Could not read shadow watermark: HTTP ${response.status}`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw new Error('Expected exactly one shadow incremental watermark');
  }
  return rows[0];
}
const beforeProduction = await publicWatermark();
const beforeShadow = await shadowWatermark();
const response = await fetch(`${base}/functions/v1/sync-incremental-product-shadow`, {
  method: 'POST',
  headers: { ...headers, 'x-cron-secret': cronSecret },
  body: '{}',
  signal: AbortSignal.timeout(180000),
});
let result;
try { result = await response.json(); } catch { result = null; }
if (!response.ok || !result?.ok || !Array.isArray(result.days)
    || !result.refresh || !result.processed_through) {
  throw new Error(`Shadow Edge canary did not pass: HTTP ${response.status}; inspect secured Edge logs`);
}
const afterProduction = await publicWatermark();
const afterShadow = await shadowWatermark();
if (JSON.stringify(beforeProduction) !== JSON.stringify(afterProduction)) {
  throw new Error('Legacy ingestion watermark changed during canary. Isolation cannot be established');
}
if (afterShadow.last_success_date !== result.processed_through) {
  throw new Error('Shadow processed-through date does not match shadow watermark');
}
const num = (name) => result.days.reduce((a, x) => a + (Number(x[name]) || 0), 0);
const stats = {
  status: 'PASS',
  function: 'sync-incremental-product-shadow',
  http_status: response.status,
  days_processed: result.days.length,
  inserted: num('inserted'),
  updated: num('updated'),
  identity_mismatches: num('identity_mismatches'),
  processed_through: result.processed_through,
  backlog_pending: Boolean(result.backlog_pending),
  source_watermark_unchanged: true,
  shadow_watermark_advanced_or_reaffirmed: afterShadow.last_success_date,
  shadow_watermark_before: beforeShadow.last_success_date,
  refresh_counts_valid: Object.values(result.refresh).every(x => Number.isFinite(Number(x))),
};
if (!stats.refresh_counts_valid || stats.identity_mismatches !== 0) {
  throw new Error('Shadow canary reported invalid refresh counts or identity mismatches');
}
console.log(JSON.stringify(stats, null, 2));
