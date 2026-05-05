---
summary: "小米 Mimo provider notes: cookie auth, balance endpoint, and setup."
read_when:
  - Adding or modifying the 小米 Mimo provider
  - Debugging Mimo cookie import or balance fetching
  - Explaining Mimo setup and limitations to users
---

# 小米 Mimo Provider

小米 Mimo provider tracks your current balance from the Xiaomi Mimo console.

## Features

- **Balance display**: Shows the current Mimo balance as provider identity text.
- **Cookie-based auth**: Uses browser cookies or a pasted `Cookie:` header.
- **Near-real-time updates**: Balance usually reflects within a few minutes.

## Setup

1. Open **Settings → Providers**
2. Enable **小米 Mimo**
3. Leave **Cookie source** on **Auto** (recommended)

### Manual cookie import (optional)

1. Open `https://platform.xiaomimimo.com/#/console/balance`
2. Copy a `Cookie:` header from your browser’s Network tab
3. Paste it into **小米 Mimo → Cookie source → Manual**

## How it works

- Fetches `GET https://platform.xiaomimimo.com/api/v1/balance`
- Requires the `api-platform_serviceToken` and `userId` cookies
- Accepts optional Mimo cookies like `api-platform_ph` and `api-platform_slh` when present
- Supports `MIMO_API_URL` to override the base API URL for testing

## Limitations

- Mimo currently exposes **balance only**
- Token cost, status polling, debug log output, and widgets are not supported yet

## Troubleshooting

### “No 小米 Mimo browser session found”

Log in at `https://platform.xiaomimimo.com/#/console/balance` in Chrome, then refresh CodexBar.

### “小米 Mimo requires the api-platform_serviceToken and userId cookies”

The pasted header or imported browser session is missing required cookies. Re-copy the request from the balance page after logging in again.

### “小米 Mimo browser session expired”

Your Mimo login is stale. Sign out and back in on the Mimo site, then refresh CodexBar.
