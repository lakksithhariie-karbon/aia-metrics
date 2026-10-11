<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## AI-agent execution contract: Engineering & Delivery

This policy applies to local coding agents, including **DeepSeek Harness (dsh)**.
These instructions are subordinate to the human's explicit decisions. They do
not authorize work on their own. DeepSeek executes **only one approved task
packet at a time**. ChatGPT owns architecture, UI/design, acceptance criteria,
review, and final technical sign-off; the user owns release approval.

### Before editing

1. Confirm `git status --short`, the current branch, the exact base commit
   and the allowed files named in the approved task packet.
2. Summarize in two or three sentences what you will change, the test plan,
   and any ambiguous requirement. Stop and ask if the task is underspecified.
3. Work in a task-specific branch, not `main`. While delivery PR #22 remains
   unmerged, branch from `fix/jira-data-foundation-v1` unless the task packet
   explicitly states another base.
4. Review the Next.js version-specific rules above before editing Next files.

### Boundaries (mandatory)

- Modify **only** files explicitly authorized in the task packet. No opportunistic
  refactors, package upgrades, unrelated formatting, or bulk rewrites.
- Preserve Product Overview, Retention, Companies, and the shared page grid
  unless they are specifically in scope.
- Do not merge a PR, force-push, publish/alias a Vercel production deployment,
  modify production environment variables, or execute live Supabase migrations.
  Prepare migration SQL for review if explicitly requested. The reviewer handles
  production changes after user authorization.
- Never inspect, print, commit, or paste API tokens, service-role keys, Vault
  secret values, or `.env*` contents. Use variable names and test fixtures only.
- Do not change Jira ingestion, reporting denominators, schema, or authentication
  while working on UI tasks. Metric calculations must remain in audited source
  readers, with corresponding totals and drill evidence reconciled.
- If tests fail or a result cannot be verified, report the exact failure.
  Never substitute screenshot numbers, silent fallbacks, or invented data.
- Use workspace-scoped file permissions with approval prompts. Do not select
  unrestricted/full-access execution for routine tasks.

### Required deliverable for each task

1. Base branch and starting SHA; the resulting commit SHA / PR link.
2. Changed-file list and `git diff --stat` plus a short explanation of each
   change and what was deliberately left unchanged.
3. Exact commands executed, exit status, failing tests and any important
   warnings. For this app, run `npm run build` unless the approved task packet
   authorizes a smaller validation scope.
4. For UI: local screenshot or browser reproduction details. For data:
   read-only source-versus-report parity checks and sample output without
   secrets or personal records.
5. Remaining uncertainty and anything needing ChatGPT/user approval.

**Stop after delivering the requested slice.** Do not start the next task
without a new approved task packet. A successful local test is not production
approval; ChatGPT reviews the diff and independent evidence first.
