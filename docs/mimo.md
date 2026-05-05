---
summary: "小米的 Mihomo provider notes: cookie auth, balance endpoint, and setup."
read_when:
  - Adding or modifying the 小米的 Mihomo provider
  - Debugging Mihomo cookie import or balance fetching
  - Explaining Mihomo setup and limitations to users
---

# 小米的 Mihomo Provider

小米的 Mihomo provider tracks your current balance from the Xiaomi Mihomo console.

## Features

- **Balance display**: Shows the current Mihomo balance as provider identity text.
- **Cookie-based auth**: Uses browser cookies or a pasted `Cookie:` header.
- **Near-real-time updates**: Balance usually reflects within a few minutes.

## Setup

1. Open **Settings → Providers**
2. Enable **小米的 Mihomo**
3. Leave **Cookie source** on **Auto** (recommended)

### Manual cookie import (optional)

1. Open `https://platform.xiaomimimo.com/#/console/balance`
2. Copy a `Cookie:` header from your browser’s Network tab
3. Paste it into **小米的 Mihomo → Cookie source → Manual**

## How it works

- Fetches `GET https://platform.xiaomimimo.com/api/v1/balance`
- Requires the `api-platform_serviceToken` and `userId` cookies
- Accepts optional Mihomo cookies like `api-platform_ph` and `api-platform_slh` when present
- Supports `MIMO_API_URL` to override the base API URL for testing

## Limitations

- Mihomo currently exposes **balance only**
- Token cost, status polling, debug log output, and widgets are not supported yet

## Troubleshooting

### “No 小米的 Mihomo browser session found”

Log in at `https://platform.xiaomimimo.com/#/console/balance` in Chrome, then refresh CodexBar.

### “小米的 Mihomo requires the api-platform_serviceToken and userId cookies”

The pasted header or imported browser session is missing required cookies. Re-copy the request from the balance page after logging in again.

### “小米的 Mihomo browser session expired”

Your Mihomo login is stale. Sign out and back in on the Mihomo site, then refresh CodexBar.
