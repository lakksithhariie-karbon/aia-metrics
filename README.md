# AI Accountant — Next.js UI foundation

Independent Next.js App Router + React + TypeScript application, built from the supplied Product Overview HTML. No backend credentials or Supabase connection required.

## Local preview

```sh
npm install
npm run dev
```

Open http://localhost:8953/overview. The root redirects there. `npm run build` and `npm start` provide the production build/start workflow. Vercel Root Directory: `ui-shells/product-overview`, preset Next.js, default output/build settings.

## Structure

- `app/`: App Router layout, entry route, original CSS in original order.
- `components/prototype-surface.tsx`: React boundary and ordered runtime loading.
- `lib/prototype/markup.ts`: trusted original body markup, extracted without rewriting the design.
- `public/prototype/runtime-*.js`: original interactive scripts in original execution order.
- `reference/aia-product-overview-v2.html`: untouched design source.
- `public/index.html`: original standalone reference preview.

## Fidelity and implementation boundary

The entire supplied UI remains available: overview, its navigation, date controls, chart interactions, exports, record drills and company views. Copy, style rules and script contents are preserved. No new visual elements or design system were introduced.

This is a Next.js application with a deliberately isolated **imperative prototype surface**, not yet a complete rewrite into React-controlled chart/table/form components. React does not reconcile the descendants managed by the original scripts. The scripts initialize once per full document load; use the prototype's own navigation within the surface. Future React navigation/remounting requires migrating its lifecycle and event cleanup first.

All analytics remain prototype fixtures and simulations. Do not mistake this for the production data layer. Supabase integration should use typed adapters to the reviewed APIs; replace complete surfaces incrementally, preserving this reference. Never interpolate API/user text into the trusted markup module. Keep secrets on the server.

## Production direction

Next.js + TypeScript on Vercel, existing Supabase Postgres, authenticated server API routes, published summaries and paginated drills. Ingestion and heavy analytics publication run separately from page requests. Serve last-good generations during failed refreshes and preserve auth boundaries in caches. Supabase SSR authentication can use `@supabase/ssr`; it is not configured in this UI-only foundation.

Sources:
- https://vercel.com/docs/frameworks/full-stack/nextjs
- https://supabase.com/docs/guides/auth/server-side/creating-a-client
- https://supabase.com/docs/guides/database/connecting-to-postgres

## V2 update

Updated all markup, CSS and both runtime scripts from v2. The original v1 and v2 references are retained. The only deliberate override is the previously requested removal of the generic “Distinct users across companies…” helper row in WAU/MAU drills. Other contextual metric explanations remain. Versioned script filenames avoid serving the v1 runtime with v2 markup; reload the page after an update.

V2 adds contextual report drills, journey stage bars and workflow tabs, drill-specific table columns/tabs/statuses, and focus restoration. Its removed export/table controls remain removed. These remain fixture-based interactions, not new production analytics contracts.
