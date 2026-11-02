# AI Services: production read access (2026-11-02)

The Bill Extraction endpoint at `/api/ai-services/report` returns company-scoped reporting details. **Never expose it on an unprotected public domain.**

## Production controls

1. Vercel project `aia-metrics` (`prj_I0L4ZpkJU4VXKV0062RV0peBvqQy`) has **Vercel Authentication** enabled for **All Deployments**. This gates the entire site, including Product and Engineering, so only authorized Vercel viewers can load the routes. Visitors must sign in.
2. `AI_BILL_REPORTING_PRODUCTION_ENABLED=true` is scoped to the **production** environment. The Node.js reader refuses production reporting when the value is absent or not exactly `true`.
3. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` remain **server-only**. The private reporting RPC uses validated scope, paginated records, and no-store responses.
4. `anon` and `authenticated` must never gain access to the private reporting view or privileged RPC. Vercel Authentication is the application access boundary.

**Emergency shutoff:** change production `AI_BILL_REPORTING_PRODUCTION_ENABLED` to `false` and redeploy. Vercel protection should remain enabled during shutoff.

**Critical dependency:** If any administrator changes Vercel Authentication from All Deployments to Preview/None, **first disable the production flag and deploy the disabled build**. Otherwise the endpoint becomes reachable without the project's access boundary.

## Checks before and after release

- Verify Vercel project reports `ssoProtection.deploymentType = all`.
- Verify Vercel production env flag is present, and credentials are configured server-side.
- Run `npm run test:ai-services-shell`, `npm run typecheck`, and `npm run build`.
- Verify an unauthenticated request to `/ai-services` and `/api/ai-services/report` is redirected to Vercel login or denied.
- With an authorized session, verify GET dashboard and POST evidence both return the expected contracts and proper filters; validate displayed figures against the database reporting view.
- Monitor server-side errors. Missing historical cost/latency remain unknown; unverified units remain neutral.
- Don't send an open shareable-protection-bypass link for production customer records.

## Source note

This release addresses the production-environment kill switch, **not** missing historical source data or undefined currency/latency units.
