#!/usr/bin/env python3
"""Assert CodexBarCLI Grok usage JSON for the #4674 fork proof."""

import json
import sys


def main() -> int:
    path, mode = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    entries = payload if isinstance(payload, list) else [payload]
    entry = next(item for item in entries if item.get("provider") == "grok")
    usage = entry.get("usage") or {}
    primary = usage.get("primary")
    provider_cost = usage.get("providerCost") or {}
    balance = provider_cost.get("balance")
    source = entry.get("source")
    print(f"raw provider={entry.get('provider')} source={source}")
    print(f"raw usage.primary={json.dumps(primary)}")
    print(f"raw usage.providerCost={json.dumps(provider_cost)}")
    if mode in {"head", "enriched"}:
        assert primary is not None, "usage.primary is missing"
        assert primary.get("usedPercent") == 0, f"usedPercent={primary.get('usedPercent')}"
        assert primary.get("windowMinutes") == 10080, f"windowMinutes={primary.get('windowMinutes')}"
        assert primary.get("resetsAt"), "resetsAt is missing"
        assert source == "grok-cli", f"source={source}"
        assert balance == 1.23, f"providerCost.balance={balance}"
        print(
            "HEAD_CLI_ASSERT_OK: "
            f"source={source} usedPercent={primary.get('usedPercent')} "
            f"windowMinutes={primary.get('windowMinutes')} resetsAt={primary.get('resetsAt')} "
            f"providerCost.balance={balance}")
        return 0
    assert mode in {"wallet-only", "before"}, f"unknown mode {mode}"
    assert primary is None, f"usage.primary should stay unknown, got {json.dumps(primary)}"
    assert balance == 1.23, f"providerCost.balance={balance}"
    label = "WALLET_ONLY_CLI_ASSERT_OK" if mode == "wallet-only" else "BEFORE_CLI_ASSERT_OK"
    print(f"{label}: primary=None providerCost.balance={balance} source={source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
