---
summary: "智谱 z.ai provider data sources: API token in config/env and quota API response parsing."
read_when:
  - Debugging z.ai token storage or quota parsing
  - Updating z.ai API endpoints
---

# 智谱 z.ai provider

智谱 z.ai is API-token based. No browser cookies.

## Token sources (fallback order)
1) Config token (`~/.codexbar/config.json` → `providers[].apiKey`).
2) Environment variable `Z_AI_API_KEY`.

### Config location
- `~/.codexbar/config.json`

## API endpoint
- `GET https://api.z.ai/api/monitor/usage/quota/limit`
- BigModel (China mainland) host: `https://open.bigmodel.cn`
- Override host via Providers → 智谱 z.ai → *API region* or `Z_AI_API_HOST=open.bigmodel.cn`.
- Override the full quota URL (e.g. coding plan endpoint) via `Z_AI_QUOTA_URL=https://open.bigmodel.cn/api/coding/paas/v4`.
- Headers:
  - `authorization: Bearer <token>`
  - `accept: application/json`

## Parsing + mapping
- Response fields:
  - `data.limits[]` → each limit entry.
  - `data.planName` (or `plan`, `plan_type`, `packageName`) → plan label.
- Limit types:
  - `TOKENS_LIMIT` → primary (tokens window).
  - `TIME_LIMIT` → secondary (MCP/time window) if tokens also present.
- Window duration:
  - Unit + number → minutes/hours/days.
- Reset:
  - `nextResetTime` (epoch ms) → date.
- Usage details:
  - `usageDetails[]` per model (MCP usage list).

## Key files
- `Sources/CodexBarCore/Providers/Zai/ZaiUsageStats.swift`
- `Sources/CodexBarCore/Providers/Zai/ZaiSettingsReader.swift`
- `Sources/CodexBar/ZaiTokenStore.swift` (legacy migration helper)
