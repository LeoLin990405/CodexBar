#!/usr/bin/env python3
"""Create the synthetic `grok` ACP fixture for the #4674 fork proof.

The fixture answers the same JSON-RPC handshake as the hermetic unit-test
fixture, with a wallet-only credits payload for an active weekly period
(start = now - 3 days, end = now + 4 days, prepaid balance = $1.23).
"""

import json
import os
import sys
import time


def main() -> int:
    fixture = sys.argv[1]
    home = os.path.join(fixture, "home")
    grok_home = os.path.join(home, ".grok")
    os.makedirs(grok_home, exist_ok=True)

    now = int(time.time())
    start = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 3 * 86400))
    end = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now + 4 * 86400))

    initialize = json.dumps({"jsonrpc": "2.0", "id": 1, "result": {}})
    billing = json.dumps({
        "jsonrpc": "2.0",
        "id": 2,
        "result": {
            "config": {
                "currentPeriod": {
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": start,
                    "end": end,
                },
                "prepaidBalance": {"val": 123},
            },
            "subscription_tier": "SuperGrok Heavy",
        },
    })
    script = f"""#!/bin/sh
if [ "$1" = "--version" ]; then
  printf '%s\\n' 'grok synthetic-version'
  exit 0
fi
IFS= read -r _initialize
printf '%s\\n' '{initialize}'
IFS= read -r _billing || exit 0
printf '%s\\n' '{billing}'
"""
    binary = os.path.join(fixture, "grok-fixture")
    with open(binary, "w", encoding="utf-8") as handle:
        handle.write(script)
    os.chmod(binary, 0o755)

    auth = {
        "https://auth.x.ai::fake-client": {
            "key": "synthetic-token",
            "refresh_token": "synthetic-refresh",
            "email": "grok@example.com",
            "auth_mode": "oidc",
            "principal_type": "User",
            "expires_at": "2099-01-01T00:00:00Z",
            "user_id": "synthetic-user",
            "team_id": None,
        },
    }
    with open(os.path.join(grok_home, "auth.json"), "w", encoding="utf-8") as handle:
        json.dump(auth, handle)
    print(f"fixture ready: {fixture} period {start} .. {end}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
