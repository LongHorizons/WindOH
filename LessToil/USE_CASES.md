# LessToil — Use Cases

> Twelve real-world scenarios demonstrating how LessToil transforms Claude Code from a text-search assistant into a structurally-aware engineering partner.

Each use case includes the concrete SQL queries, hook behaviors, and slash commands involved — so you can reproduce these workflows in your own projects.

---

## Table of Contents

1. [Safe Refactoring](#use-case-1-safe-refactoring)
2. [Preventing Duplicate Utilities](#use-case-2-preventing-duplicate-utilities)
3. [Architectural Onboarding](#use-case-3-architectural-onboarding)
4. [Dead Code Detection](#use-case-4-dead-code-detection)
5. [Security Audit Preparation](#use-case-5-security-audit-preparation)
6. [Cross-Team Coordination](#use-case-6-cross-team-coordination)
7. [Monorepo Navigation](#use-case-7-monorepo-navigation)
8. [Test Coverage Gap Analysis](#use-case-8-test-coverage-gap-analysis)
9. [Migration Planning](#use-case-9-migration-planning)
10. [Pull Request Review](#use-case-10-pull-request-review)
11. [Architectural Drift Monitoring](#use-case-11-architectural-drift-monitoring)
12. [Cost-Aware Refactoring](#use-case-12-cost-aware-refactoring)

---

## Use Case 1: Safe Refactoring

### Scenario

You need to rename a core utility function `formatDate` that is used across the entire codebase. Without structural awareness, you grep for "formatDate" and hope you found every usage — dynamic imports, re-exports, aliased imports, and transitive dependencies often go undetected.

### Workflow

**Step 1 — Assess impact before touching code:**

```
User: "What's the impact of changing formatDate?"
```

The query skill auto-activates and executes a recursive CTE through the call graph:

```sql
WITH RECURSIVE dependents AS (
    SELECT s.id, s.name, f.file_path, 1 AS depth
    FROM call_edges ce
    JOIN symbols s ON ce.caller_id = s.id
    JOIN files f ON s.file_id = f.id
    WHERE ce.callee_name = 'formatDate'
    UNION ALL
    SELECT s.id, s.name, f.file_path, d.depth + 1
    FROM call_edges ce
    JOIN symbols s ON ce.caller_id = s.id
    JOIN files f ON s.file_id = f.id
    JOIN dependents d ON ce.callee_name = d.name
    WHERE d.depth < 10
)
SELECT DISTINCT file_path, name, depth FROM dependents
ORDER BY depth, file_path;
```

**Result**: 47 callers across 23 files, with 12 test files identified.

**Step 2 — The PreToolUse hook fires automatically when editing begins:**

```
Impact: Editing 1 file(s) affects 47 callers in 23 files across domains: ui, api, data-access.
Tests potentially affected: components/__tests__/DateDisplay.test.tsx, utils/__tests__/formatting.test.ts, and 10 more
```

**Step 3 — Execute with confidence**: The agent knows exactly which 23 files need updating, in dependency order (callees first, callers last). All 12 test files are identified for updating. No caller is missed.

### Without LessToil

- Grep for "formatDate" → misses dynamic usages, re-exports, and aliased imports
- Manually track each usage → 30+ minutes of search
- Forget test files → CI fails on the first push
- Miss 2-3 callers → bugs discovered in production next sprint

### Key Mechanism

Recursive CTE call graph traversal with depth limiting, combined with PreToolUse impact injection, replaces manual dependency tracing.

---

## Use Case 2: Preventing Duplicate Utilities

### Scenario

You ask Claude Code to create a JWT token validation function. Unaware of the existing codebase, it creates `validateJWT()` — which becomes the fourth implementation of the same logic.

### Workflow

**Step 1 — The PreToolUse hook fires before the Write tool executes:**

```
Duplicate risk: `validateJWT` already exists in:
  src/auth/jwt.ts (function, line 42),
  src/middleware/tokenValidator.ts (function, line 78),
  src/legacy/oldAuth.ts (function, line 156).
Consider reusing or extending the canonical implementation at src/auth/jwt.ts.
```

**Step 2 — Agent adapts**: Instead of creating a fourth implementation, the agent imports the canonical `validateJWT` from `src/auth/jwt.ts` and extends it if needed.

**How it works**:
1. PreToolUse extracts function and class names from the pending edit content
2. Queries `symbols` table for existing definitions with matching names
3. Additionally queries `similarity_groups` via SimHash for structurally similar code at different names
4. Reports all matches with file paths and line numbers

### Without LessToil

- Agent creates `src/utils/validateJWT.ts` — the 4th JWT validator
- Each implementation has slightly different behavior (bugs fixed in one but not the others)
- Future developers don't know which implementation is canonical
- 6 months later: "Why do we have four JWT validators?" — consolidation costs 4-8 hours

### Impact Over Time

For a team creating ~10 new utility functions per sprint, the plugin prevents 2-3 accidental duplicates per sprint — each of which would cost 4-8 hours to discover and consolidate later.

---

## Use Case 3: Architectural Onboarding

### Scenario

A new developer joins the team and asks: "How does payment processing work in this codebase?"

### Workflow

**Step 1 — Query the domain map:**

```
User: "How does payment processing work?"
```

The agent queries the `domains` table:

```sql
SELECT description, entry_points FROM domains WHERE name = 'payments';
```

→ "Payment processing, billing, invoicing, subscriptions"
→ Entry points: `src/billing/checkout.ts:30`, `src/billing/webhook.ts:15`

**Step 2 — Domain map is presented:**

```
### payments [SECURITY BOUNDARY]

Entry points:
  - src/billing/checkout.ts:30 (createCheckoutSession)
  - src/billing/webhook.ts:15 (handleStripeWebhook)

Key files (47 total in domain):
  - src/billing/checkout.ts
  - src/billing/invoice.ts
  - src/billing/subscription.ts
  - src/stripe/client.ts
  - src/billing/webhook.ts

Call flow:
  CheckoutPage.onSubmit()
    → createCheckoutSession()
      → stripe.checkout.sessions.create()
      → saveOrder()
        → OrderRepo.insert()
      → emitCheckoutEvent()
        → EmailService.sendConfirmation()
        → Analytics.trackPurchase()

Security boundaries:
  - Stripe API key in src/stripe/client.ts (taint source)
  - Webhook signature verification in src/billing/webhook.ts
```

**Step 3**: The developer has a complete mental model of the payments subsystem — entry points, critical files, call flow, and security boundaries — in under 10 seconds.

### Without LessToil

- Developer searches for "payment" → 200+ grep results
- Reads 15-20 files across multiple sessions trying to understand the flow
- Misses the webhook handler entirely (it's in `billing/`, not `payment/`)
- Takes 2-4 hours to build the same mental model
- May not discover the security boundary implications for days

---

## Use Case 4: Dead Code Detection

### Scenario

After six months of rapid iteration, your team suspects there are unused utility functions, deprecated API endpoints, and abandoned components cluttering the codebase.

### Workflow

```
User: "Find unused functions"
```

The `/index-graph --orphans` command executes:

```sql
SELECT s.name, s.kind, f.file_path, s.start_line
FROM symbols s
JOIN files f ON s.file_id = f.id
WHERE s.kind IN ('function', 'method')
  AND s.name NOT IN (
    SELECT DISTINCT ce.callee_name FROM call_edges
    WHERE ce.callee_name IS NOT NULL
  )
ORDER BY f.file_path, s.start_line
LIMIT 50;
```

**Result**: 34 functions across 18 files are never called. The agent presents them organized by file with line numbers, grouped by domain.

**Follow-up — Check the broader picture:**

```
User: "Show me dead subsystems — entire directories with no callers"
```

The stewardship scan (which runs at every SessionStart) already has this data:

```
Dead subsystems detected:
  ◇  legacy/billing-v1/ — 23 files, 0 callers in 90+ days
  ◇  experiments/ab-test-framework/ — 12 files, 0 callers
  ◇  tools/migration-scripts/2025/ — 8 files, 0 callers (historical)
```

### Without LessToil

- Manual code review takes 2-6 hours and is inherently unreliable
- "Is this still used?" becomes a recurring question in every code review
- Dead code accumulates over releases, bloating bundle sizes and slowing builds
- No one is confident enough to delete anything

### Quantified Impact

In a medium codebase (~3K files), teams typically find 30-50 orphaned functions and 2-4 dead subsystems per quarterly cleanup — representing 5-10% of the codebase that can be confidently removed.

---

## Use Case 5: Security Audit Preparation

### Scenario

Your team is preparing for a SOC 2 audit. You need to identify every security-sensitive code path: authentication, authorization, cryptography, secret handling, and PII processing.

### Workflow

**Step 1 — Enumerate security-sensitive symbols:**

```sql
SELECT s.name, s.kind, f.file_path, s.start_line
FROM symbols s JOIN files f ON s.file_id = f.id
WHERE s.security_sensitive = 1
ORDER BY f.file_path;
```

**Step 2 — Map security boundary domains:**

```sql
SELECT DISTINCT f.file_path
FROM files f
JOIN file_domains fd ON f.id = fd.file_id
JOIN domains d ON fd.domain_id = d.id
WHERE d.security_boundary = 1
ORDER BY f.file_path;
```

**Step 3 — Trace data flows across security boundaries:**

The taint tracking system (`security_provenance.py`) maps untrusted inputs to sensitive sinks:

```
Taint flows detected:
  req.body.email (src/api/controllers/user.ts:45)
    → UserService.findByEmail() [NO SECURITY CHECK]
    → UserRepo.findByEmail() [DATABASE QUERY]
  RISK: Unvalidated user input reaches database query.

  req.headers.authorization (src/middleware/auth.ts:23)
    → TokenParser.extractToken() [VALIDATION PRESENT]
    → JWT.verify() [CRYPTO OPERATION]
  SAFE: Input validated before cryptographic operation.
```

**Step 4 — Identify gaps**: The governance policy "require tests for security paths" automatically flags security-sensitive symbols without test coverage. Cross-reference with temporal risk scores to prioritize the highest-risk gaps.

### Without LessToil

- Manual grep for "auth", "token", "password", "secret" → hundreds of false positives
- Missing indirect security-sensitive paths (utility functions that process tokens but have innocuous names)
- No data flow visibility — can't distinguish validated from unvalidated taint paths
- 4-8 hours of manual review with high risk of missing critical paths

### Quantified Impact

A typical SOC 2 preparation effort drops from 40-80 hours of manual code review to 5-10 hours of targeted analysis driven by index queries.

---

## Use Case 6: Cross-Team Coordination

### Scenario

The authentication team is changing the session token format. The payments, messaging, and admin teams all need to know if they are affected.

### Workflow

**Step 1 — Map domain dependencies:**

```
User: "Which domains depend on authentication?"
```

```sql
SELECT caller_d.name AS domain, COUNT(*) AS call_edges
FROM call_edges ce
JOIN symbols caller ON ce.caller_id = caller.id
JOIN files caller_f ON caller.file_id = caller_f.id
JOIN file_domains caller_fd ON caller_f.id = caller_fd.file_id
JOIN domains caller_d ON caller_fd.domain_id = caller_d.id
JOIN symbols callee ON ce.callee_name = callee.name
JOIN files callee_f ON callee.file_id = callee_f.id
JOIN file_domains callee_fd ON callee_f.id = callee_fd.file_id
JOIN domains callee_d ON callee_fd.domain_id = callee_d.id
WHERE callee_d.name = 'authentication'
  AND caller_d.name != 'authentication'
GROUP BY caller_d.name
ORDER BY call_edges DESC;
```

```
authentication → api (891 call edges)
authentication → payments (124 call edges)
authentication → messaging (45 call edges)
authentication → ui (312 call edges)
```

**Step 2 — Drill into specific impact:**

```
User: "What exactly in payments calls auth functions?"
```

```
Symbols in 'payments' domain calling into 'authentication':
  - CheckoutService.validateSession (src/billing/checkout.ts:45)
  - InvoiceGenerator.getUserContext (src/billing/invoice.ts:78)
  - SubscriptionManager.verifyAccess (src/billing/subscription.ts:112)
```

**Result**: The payments team knows exactly what needs updating — 3 functions in 3 files. A 30-second query replaces days of Slack threads and manual code searching.

### Without LessToil

- Auth team posts in Slack: "We're changing the session format"
- Payments team: "Does this affect us?"
- Auth team: "Check where you import from `auth/`?"
- 3 days of back-and-forth, manual searching, and uncertainty
- Something inevitably gets missed

---

## Use Case 7: Monorepo Navigation

### Scenario

You maintain a monorepo with 12 packages: 3 frontends, 5 backend services, 2 shared libraries, and 2 infrastructure packages. Understanding cross-package dependencies is critical and difficult.

### Workflow

**Step 1 — Generate the domain graph:**

```
User: "Show me the package dependency graph"
```

```
Domain dependency map:
  frontend-app → api-gateway (234 call edges)
  frontend-app → shared-ui (567 call edges)
  frontend-admin → api-gateway (89 call edges)
  frontend-admin → shared-ui (234 call edges)
  api-gateway → auth-service (156 call edges)
  api-gateway → billing-service (67 call edges)
  api-gateway → shared-utils (345 call edges)
  auth-service → shared-utils (234 call edges)
  billing-service → shared-utils (123 call edges)
```

**Step 2 — Detect problems automatically:**

```
Architectural issues detected:
  ◆  shared-ui → shared-utils (45 call edges)
  ◆  shared-utils → shared-ui (12 call edges)  ← CIRCULAR DEPENDENCY
  Severity: ERROR (governance policy blocks new edges in this cycle)
```

The formal constraints module (`formal_constraints.py`) detected the circular dependency automatically. The governance policy "forbid circular dependencies" (severity: error) will block any new code that worsens the cycle.

**Step 3 — Identify coupling hotspots:**

```
User: "Which package is most coupled?"
```

The stewardship coupling analysis ranks packages by fan-out (number of distinct packages depended on) and fan-in (number of packages depending on it). The most coupled package (`shared-utils`, with 4 dependents and 3 dependencies) is flagged as a refactoring priority.

### Without LessToil

- Read each package's dependency manifest file
- Manual grep for cross-package imports — hundreds of false positives from type-only imports
- Circular dependencies remain hidden until they cause build failures or runtime deadlocks
- Hours to map for a 12-package monorepo, days for larger ones

---

## Use Case 8: Test Coverage Gap Analysis

### Scenario

A major release is approaching. You need to identify exported functions without test coverage — not line coverage from a coverage tool, but actual function-level test presence.

### Workflow

```sql
SELECT s.name, s.kind, f.file_path, s.start_line,
       d.name AS domain
FROM symbols s
JOIN files f ON s.file_id = f.id
LEFT JOIN file_domains fd ON f.id = fd.file_id
LEFT JOIN domains d ON fd.domain_id = d.id
WHERE s.kind IN ('function', 'method')
  AND s.is_exported = 1
  AND s.name NOT IN (
    SELECT DISTINCT ce.callee_name
    FROM call_edges ce
    JOIN symbols caller ON ce.caller_id = caller.id
    JOIN files caller_f ON caller.file_id = caller_f.id
    WHERE caller_f.file_path LIKE '%test%'
       OR caller_f.file_path LIKE '%spec%'
       OR caller_f.file_path LIKE '%__tests__%'
  )
ORDER BY f.file_path;
```

**Cross-reference with security sensitivity:**

```sql
-- Untested security-sensitive functions — highest priority
SELECT s.name, f.file_path, s.start_line
FROM symbols s JOIN files f ON s.file_id = f.id
WHERE s.security_sensitive = 1
  AND s.kind IN ('function', 'method')
  AND s.name NOT IN (
    SELECT DISTINCT ce.callee_name FROM call_edges ce
    JOIN symbols caller ON ce.caller_id = caller.id
    JOIN files caller_f ON caller.file_id = caller_f.id
    WHERE caller_f.file_path LIKE '%test%'
       OR caller_f.file_path LIKE '%spec%'
       OR caller_f.file_path LIKE '%__tests__%'
  )
ORDER BY f.file_path;
```

The governance policy "require tests for security paths" automatically flags violations of this query.

### Without LessToil

- Coverage tools (Istanbul, coverage.py) show line coverage percentages, not function-level test presence
- Functions "covered" by integration tests appear green but lack dedicated unit tests
- No way to prioritize by security sensitivity or business criticality
- Manual coverage report analysis is tedious and incomplete

---

## Use Case 9: Migration Planning

### Scenario

You are migrating from REST to GraphQL. You need to identify every endpoint handler, its complete call chain, shared dependencies, and downstream data access patterns — to accurately scope the migration effort.

### Workflow

**Step 1 — Enumerate all API domain symbols:**

```
User: "Show me all API endpoint handlers and their call chains"
```

**Step 2 — Trace the call chain for each handler:**

```
GET /api/users/:id → UserController.getUser()
  → UserService.findById()
    → UserRepo.findById()      [data-access]
    → cache.get()               [caching]
  → formatUserResponse()
    → UserSerializer.toJSON()

GET /api/orders/:id → OrderController.getOrder()
  → OrderService.findById()
    → OrderRepo.findById()     [data-access]
    → UserService.findById()   ← SHARED DEPENDENCY
      → UserRepo.findById()    [data-access]
      → cache.get()             [caching]
```

**Step 3 — Identify shared dependencies:**

```
Shared dependencies across API handlers:
  UserService.findById — called by 7 endpoint handlers
  cache.get — called by 12 endpoint handlers
  validateAuth — called by 18 endpoint handlers
```

The impact analysis module shows that `UserService.findById` is called by both user and order handlers, and `cache.get` is a universal dependency. Both need careful handling during the migration — changes to either affect the entire API surface.

### Without LessToil

- Read every route file manually to build the endpoint inventory
- Trace each handler by reading implementation files — dozens of files, hours of work
- Miss indirect dependencies (shared services called by multiple handlers)
- Underestimate migration scope by 2-3x due to hidden shared dependencies
- Discovery phase alone takes days

---

## Use Case 10: Pull Request Review

### Scenario

A PR changes three files in the `auth` domain. You need to understand the blast radius before approving — not just whether the diff looks correct in isolation.

### Workflow

**Step 1 — Get changed files:**

```
User: "Analyze the impact of PR #4231"
```

The agent runs `gh pr diff 4231 --name-only` to get the changed file list, then queries the index for impact.

**Step 2 — Impact analysis output:**

```
Impact: Editing 3 file(s) affects 89 callers in 34 files across domains: auth, api, middleware, caching.

Security-sensitive symbols affected: refreshToken, validateSession, hashPassword

Tests potentially affected:
  - src/auth/__tests__/session.test.ts
  - src/auth/__tests__/jwt.test.ts
  - src/middleware/__tests__/auth-middleware.test.ts
  - src/api/__tests__/user-routes.test.ts

Transitive dependents (depth 1-3):
  - UserController.getProfile (src/api/controllers/user.ts) [depth 1]
  - AdminMiddleware.requireAuth (src/middleware/admin.ts) [depth 1]
  - WebSocketAuth.upgrade (src/ws/auth.ts) [depth 2]

Stewardship note: src/auth/session.ts already flagged as over-complex (1,247 lines, 47 methods).
Consider splitting before adding more complexity to this file.

Governance status: All invariants pass. Policy warning: src/auth/session.ts exceeds max file size (1,247 > 1000).
```

**Step 3 — Informed review**: The reviewer now knows:
- Which 34 downstream files to check for compatibility
- Which 4 test files should have been updated in the PR
- That a pre-existing stewardship concern exists on one of the changed files
- That security-sensitive symbols are affected, requiring extra scrutiny

### Without LessToil

- Review the diff in isolation
- "Looks good to me" — approve
- Production breaks because a downstream caller in a different package wasn't updated
- Rollback, investigate, fix — hours of incident response time
- Postmortem: "We didn't realize `validateSession` was called from the WebSocket handler"

---

## Use Case 11: Architectural Drift Monitoring

### Scenario

Your team has grown from 3 to 15 engineers over 18 months. Coding conventions are diverging, and you want to catch drift before it becomes systemic technical debt.

### Workflow

**Every SessionStart, the drift detection module runs automatically:**

```
──  ARCHITECTURAL DRIFT
Avg drift: 0.12    High-drift files: 3    Trend: improving (-0.03 since last week)

  Naming divergence:
    ◇  src/new-module/ — 12 files using snake_case in a camelCase TypeScript project
    ◇  Detected 2 weeks ago, trend: stable (not growing)

  Style outliers:
    ◇  src/contracts/payment.ts — class-based when project convention is functional
    ◇  Detected 4 weeks ago, trend: stable

  Anti-pattern emergence:
    ◆  src/utils/god-object.ts — 47 methods, 3,200 lines (god object detected)
    ◆  Detected 1 week ago, trend: worsening (+2 methods this week)

  Framework creep:
    ◇  3 HTTP clients detected: axios (dominant, 89% of calls), fetch (7 calls), got (3 calls)
    ◇  Detected 3 weeks ago, trend: improving (was 4 clients, got consolidated)
```

The drift scores persist across sessions in the SQLite database, enabling trend analysis. You can track whether each drift category is improving, stable, or worsening over time.

### Without LessToil

- Drift accumulates silently for months
- Discovered only during painful code reviews or when a rewrite becomes necessary
- No quantitative measure of when conventions started diverging
- No trend data — can't tell if the problem is growing or shrinking
- Remediation is reactive (triggered by crisis) rather than proactive

---

## Use Case 12: Cost-Aware Refactoring

### Scenario

You need to prioritize technical debt remediation across multiple competing concerns. Gut-feel prioritization leads to fixing visible but low-impact issues while high-ROI fixes go unaddressed.

### Workflow

The economics module (`economics.py`) combines structural data with cost models:

```
User: "What's the most cost-effective refactoring to do first?"

──  ECONOMICS — Prioritized Refactoring Candidates
Estimated costs (build + CI + cloud + dev-hours):

  1. Circular dependency: shared-ui ↔ shared-utils
     CI cache miss cost: ~$300/month (estimated from CI timing data)
     Build time impact: +45s per full build
     Fix effort: 4 hours
     ROI: 0.5 months  ← BEST ROI

  2. Dead subsystem: legacy/billing-v1/
     Maintenance cost: ~$2,400/month (estimated from churn + bug density)
     Removal effort: 8 hours
     ROI: 1.2 months

  3. Over-complex file: payment/handler.ts (1,247 lines)
     Bug-fix cost: ~$800/month (based on churn rate + bug-fix density)
     Refactor effort: 16 hours
     ROI: 2.1 months
```

**How costs are estimated:**

| Cost Factor | Data Source |
|-------------|------------|
| Build time impact | Call graph depth × average compilation time per file |
| CI cache miss cost | Circular dependency detection × CI runner cost per minute |
| Maintenance cost | Temporal risk score × developer hour cost × churn frequency |
| Bug-fix cost | Bug-fix density from git history × average fix time × developer cost |
| Cloud cost impact | Security-sensitive paths × estimated latency impact × request volume |
| Developer hour cost | Configurable rate (default: industry average for region) |

### Without LessToil

- "What should we refactor first?" → gut feeling or loudest stakeholder
- No quantitative basis for comparing options with different cost structures
- High-ROI fixes (circular dependencies, dead subsystems) missed in favor of visible but low-impact cleanups
- Refactoring budget is spent suboptimally

---

## Summary Matrix

| Task | Without Plugin | With Plugin | Primary Mechanism |
|------|---------------|-------------|-------------------|
| Find all callers of a function | grep + manual filtering (15-45 min) | Single SQL query (< 1s) | `call_edges` recursive CTE |
| Impact analysis before refactor | Manual code reading (30-90 min) | Automatic PreToolUse injection | `impact.py` + PreToolUse hook |
| Duplicate detection | None (creates duplicates silently) | Warns before creation | SimHash + symbol lookup |
| Architectural overview | Read dozens of files (hours) | Domain map query (seconds) | `domains` + `file_domains` tables |
| Dead code detection | Manual review (2-6 hours) | `/index-graph --orphans` (seconds) | Orphan SQL query |
| Security audit prep | grep for keywords (incomplete, 4-8 hours) | Query security boundaries + taint flows (minutes) | `security_provenance.py` |
| Cross-team dependency check | Slack threads + manual search (hours to days) | Domain dependency graph (seconds) | Cross-domain call edge query |
| Onboarding a new developer | Days of reading code | Domain maps + call flows (minutes) | Domains + call graph queries |
| PR review blast radius | Read diff in isolation | Full transitive impact analysis | PreToolUse impact injection |
| Migration scope estimation | Manual tracing (days) | Call chain analysis (minutes) | Recursive CTE call tracing |
| Drift monitoring | Reactive (noticed in code review) | Proactive (every session, with trends) | `drift_detection.py` |
| Cost-aware prioritization | Gut feeling | Quantitative ROI ranking | `economics.py` |
