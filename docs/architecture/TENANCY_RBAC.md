# Tenancy and RBAC

**Status: Roadmap.** The current WindOH deployment model assumes a single tenant (one security operations team) with all analysts having full access. Multi-tenancy and role-based access control are designed as extensions.

---

## Current State

- Single MongoDB database (`windoh`) with no collection-level access control
- Single Redis instance with no key namespace isolation
- No authentication layer in the WindOH API (relies on network isolation)
- All analysts share the same view of all data

## Target Architecture

### Tenancy Model

```
┌────────────────────────────────────────────────────────────────────┐
│                         WindOH Platform                             │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ Tenant A     │  │ Tenant B     │  │ Tenant C     │              │
│  │ (SOC Team 1) │  │ (SOC Team 2) │  │ (IR Team)    │              │
│  │              │  │              │  │              │              │
│  │ Own agents   │  │ Own agents   │  │ Own agents   │              │
│  │ Own tokens   │  │ Own tokens   │  │ Own tokens   │              │
│  │ Own sequences│  │ Own sequences│  │ Own sequences│              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                       │
│         ▼                 ▼                 ▼                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │               Shared Infrastructure                          │  │
│  │  • Elasticsearch (index per tenant or shared with tenant_id) │  │
│  │  • Local LLM (shared, no tenant data in prompts beyond event)│  │
│  │  • SearXNG (shared, no tenant context)                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### Isolation Strategy

| Resource | Isolation Method | Rationale |
|---|---|---|
| **MongoDB** | Database-per-tenant (`windoh_tenant_a`, `windoh_tenant_b`) | Strongest isolation. Atlas supports this natively. |
| **Redis** | Key prefix per tenant (`tenant:a:bull:enrichment:*`) | Single Redis instance with namespace isolation. |
| **Elasticsearch** | Index pattern per tenant (`tenant_a-longhorizons-events`) or `tenant_id` field with document-level security | Dependent on ES security features. |
| **LLM** | No tenant isolation (stateless) | The LLM does not retain state between requests. Prompts contain only the event being enriched, not tenant context. |

### Database-Per-Tenant Implementation

```typescript
// lib/tenant.ts
async function getTenantDB(tenantId: string): Promise<Db> {
  const client = await MongoClient.connect(MONGODB_URI);
  return client.db(`windoh_${tenantId}`);
}

// API middleware: resolve tenant from auth context
async function tenantMiddleware(req: NextRequest) {
  const tenantId = await resolveTenantFromAuth(req);
  req.tenantDB = await getTenantDB(tenantId);
}
```

---

## RBAC Model

### Roles

| Role | Permissions |
|---|---|
| **Viewer** | Read tokens, events, sequences. View dashboards. Cannot trigger enrichment, ART tests, or IOC lookups. |
| **Analyst** | Viewer + trigger enrichment, run IOC lookups, view coverage reports. Cannot modify system configuration. |
| **Detection Engineer** | Analyst + create/edit detection rules, manage ART test mappings, modify Markov model parameters. |
| **Admin** | Full access: manage tenants, configure LLM endpoint, manage API keys, view audit logs. |

### Permission Matrix

| Operation | Viewer | Analyst | Detection Engineer | Admin |
|---|---|---|---|---|
| `tokens:read` | ✓ | ✓ | ✓ | ✓ |
| `tokens:enrich` | | ✓ | ✓ | ✓ |
| `events:read` | ✓ | ✓ | ✓ | ✓ |
| `coverage:read` | ✓ | ✓ | ✓ | ✓ |
| `ioc:lookup` | | ✓ | ✓ | ✓ |
| `art:execute` | | | ✓ | ✓ |
| `detection:write` | | | ✓ | ✓ |
| `markov:configure` | | | ✓ | ✓ |
| `system:configure` | | | | ✓ |
| `tenants:manage` | | | | ✓ |
| `audit:read` | | | | ✓ |

### Authentication

Planned:
- **OIDC / OAuth2** (Auth0, Okta, Keycloak) for human analysts
- **API Key** for service accounts (agent registration, CI/CD integration)
- NextAuth.js integration for Next.js API routes

```typescript
// middleware.ts (planned)
import { getToken } from 'next-auth/jwt';

export async function middleware(req: NextRequest) {
  const token = await getToken({ req });
  if (!token) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  req.tenantId = token.tenant_id;
  req.role = token.role;
  
  // Check permission for the requested operation
  if (!hasPermission(req.role, req.nextUrl.pathname, req.method)) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  }
}

export const config = {
  matcher: '/api/:path*',
};
```

---

## Audit Logging

All operations that modify data or system state must produce audit events:

```typescript
// lib/audit.ts
interface AuditEvent {
  timestamp: Date;
  tenantId: string;
  userId: string;
  role: string;
  operation: string;     // "tokens:enrich", "ioc:lookup", "system:configure"
  resource: string;      // stable_token, IP address, config key
  outcome: "success" | "failure";
  metadata: Record<string, unknown>;
}
```

Audit events are stored in a dedicated MongoDB collection (`audit_logs`) with a TTL index for retention (default: 365 days).

---

## Implementation Order

1. **Phase 1: Authentication layer** — NextAuth.js integration. Single-tenant with role-based access. No data isolation changes.
2. **Phase 2: Audit logging** — All state-changing operations produce audit events. Read operations are logged at aggregate level.
3. **Phase 3: Database-per-tenant** — Migration of single `windoh` database to `windoh_<tenant_id>`. Tenant provisioning API.
4. **Phase 4: API key management** — Self-service API key generation for service accounts with scoped permissions.
