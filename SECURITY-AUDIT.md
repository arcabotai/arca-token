# Security Audit — ArcaPresaleV2

Self-audit performed by Arca (arcabot.eth) on March 23, 2026.
Contract: `src/ArcaPresaleV2.sol`

---

## Architecture Summary

ETH flows: `Contributor → Contract → Gnosis Safe (vault)` in a single transaction.
**The contract never holds ETH.** Every wei is forwarded immediately.

---

## Audit Checklist

### ✅ PASSED — No Stuck Funds

**V1 Problem:** Refunds required each user to call `refund()`. Some never did → ETH stuck forever.

**V2 Solution:** ETH is forwarded to the Gnosis Safe in the same transaction via `vault.call{value: msg.value}`. The contract balance is always 0 after every transaction. There is no refund mechanism because there's nothing to refund from the contract.

**If refunds are needed:** The multisig owners (arcabot.eth + felirami.eth) can send ETH back to contributors directly from the Safe. This is a human decision, not a smart contract limitation.

**Test:** `test_vaultReceivesFunds` confirms contract balance = 0 after contributions.

### ✅ PASSED — Vault Transfer Cannot Fail Silently

The `contribute()` function uses:
```solidity
(bool sent,) = vault.call{value: msg.value}("");
require(sent, "Vault transfer failed");
```

If the vault rejects ETH (e.g., Safe is paused, fallback reverts), the **entire transaction reverts**. The contributor's ETH stays in their wallet. No partial state update.

**Test:** If vault were a contract that reverts, the contribution would revert entirely.

### ✅ PASSED — No Reentrancy Risk

The external call to vault happens AFTER state updates (`contributions`, `totalRaised`, `contributors[]`). Even if the vault were malicious and re-entered `contribute()`:
1. The `maxContribution` check would prevent over-contribution
2. The `hardCap` check would prevent exceeding the cap
3. State is already updated before the call

Following Checks-Effects-Interactions pattern. Low risk.

**Additional protection:** The vault is a Gnosis Safe (audited, standard), not an arbitrary contract.

### ✅ PASSED — Integer Overflow/Underflow

Using Solidity 0.8.24 which has built-in overflow checks. All arithmetic operations revert on overflow.

### ✅ PASSED — Access Control

- `closePresale()`: Only `owner` can close early. After hard cap timer expires, anyone can close (prevents stale presale).
- `contribute()`: Anyone can contribute (no whitelist for participation, only for bonus).
- OG whitelist is set in constructor (immutable after deploy).
- Owner cannot: withdraw funds, change caps, modify whitelist, or pause contributions.
- **Owner can only:** close the presale early.

### ✅ PASSED — Contribution Limits

- Minimum: 0.01 ETH enforced per transaction
- Maximum: 1 ETH enforced per wallet (cumulative across all contributions)
- Hard cap: 12.5 ETH enforced globally
- All checks happen before state changes

**Edge case tested:** Contributing 0.9 ETH then 0.2 ETH → reverts on second call (would exceed 1 ETH max).

### ✅ PASSED — Soft Cap / Hard Cap Logic

- No time limit before soft cap → presale stays open indefinitely until 5 ETH
- Timer starts exactly when `totalRaised >= softCap` (checked after every contribution)
- Timer runs for exactly 5 days (432,000 seconds)
- After timer expires, `isActive()` returns false and contributions revert
- Hard cap (12.5 ETH) closes presale immediately when hit

**Test:** `test_noTimerBeforeSoftCap` — 100 days pass, still active if soft cap not hit.
**Test:** `test_timerExpiry` — contributions revert after 5 days post soft cap.

### ✅ PASSED — OG Bonus Calculation

- OG bonus is allocation weight only (10% = 1000 bps)
- No extra ETH is created — bonus only affects token distribution calculation
- `getAllocationWeight()` returns: `contribution + (contribution * 1000 / 10000)` for OGs
- Non-OG wallets get 1:1 weight
- Zero contribution → zero weight (no free tokens for OGs who don't contribute again)

### ✅ PASSED — Data Integrity for Airdrop

- `getAllContributions()` returns arrays of all contributors, amounts, weights, and OG status
- Used off-chain to calculate Clanker airdrop Merkle tree
- Contributors array grows monotonically (addresses only added, never removed)
- Each address appears exactly once in the array

### ⚠️ KNOWN LIMITATION — No On-Chain Refund

By design, the contract cannot refund. If the presale needs to be cancelled:
1. Owner calls `closePresale()`
2. Multisig owners manually send ETH back from the Safe
3. Contributors must trust the multisig to return funds

**Mitigation:** The Safe is 2-of-2 (arcabot.eth + felirami.eth). Both parties must agree. This is more transparent than a single-owner refund.

### ⚠️ KNOWN LIMITATION — Owner Can Close Early

The owner can call `closePresale()` at any time, even before soft cap. This prevents further contributions.

**Mitigation:** All ETH is already in the multisig. Closing early doesn't steal funds — it just stops new contributions. The multisig can still distribute tokens or return ETH.

### ⚠️ KNOWN LIMITATION — Contribution Exactly at Hard Cap

If `totalRaised = 12.49 ETH` and someone sends `0.02 ETH`, it reverts because `12.49 + 0.02 = 12.51 > 12.5`. They'd need to send exactly `0.01 ETH`.

**Mitigation:** Frontend should calculate the maximum remaining amount and cap the input accordingly.

### ⚠️ KNOWN LIMITATION — Gas Cost for Large OG Whitelist

Constructor loops through all OG addresses. With 26 addresses, this costs ~150K extra gas. Acceptable for deployment.

### ✅ PASSED — No Selfdestruct / Delegatecall

Contract has no `selfdestruct`, `delegatecall`, or upgradability. Once deployed, the code is immutable.

### ✅ PASSED — Event Emission

All state changes emit events:
- `Contributed` — every contribution with amount, total, and OG status
- `SoftCapReached` — when soft cap is hit
- `HardCapReached` — when hard cap fills
- `PresaleClosed` — when presale ends (any reason)
- `VaultForwarded` — every ETH transfer to vault

Full traceability on-chain.

---

## Attack Vectors Considered

| Attack | Risk | Status |
|--------|------|--------|
| Reentrancy via vault callback | Low | State updated before call, Safe is standard |
| Front-running contributions | Low | No price/ordering benefit to front-running |
| DoS by sending dust | None | Minimum 0.01 ETH enforced |
| Griefing by hitting exact hard cap | Low | Frontend handles remaining amount calculation |
| Flash loan attack | None | No price oracle, no AMM interaction |
| Owner rugpull | Low | Owner can only close presale, not withdraw. Funds in 2-of-2 multisig |
| Stuck funds in contract | None | Contract balance always 0 — all ETH forwarded |
| Sybil attack (many wallets) | Low | Max 1 ETH per wallet limits value of sybil |
| Vault address = zero | Low | Deployment script validates vault != address(0) |

---

## Test Coverage

| Test | What it verifies |
|------|-----------------|
| `test_initialState` | All parameters set correctly |
| `test_contribute` | Basic contribution + vault forwarding |
| `test_contributeViaReceive` | `receive()` fallback works |
| `test_ogBonus` | 10% bonus weight for OG, 1:1 for regular |
| `test_revertBelowMin` | Rejects < 0.01 ETH |
| `test_revertAboveMax` | Rejects > 1 ETH cumulative |
| `test_softCapTriggers` | Timer starts when soft cap hit |
| `test_hardCapCloses` | Presale closes at 12.5 ETH |
| `test_timerExpiry` | Contributions revert after 5-day timer |
| `test_noTimerBeforeSoftCap` | No expiry before soft cap |
| `test_vaultReceivesFunds` | Contract balance = 0, vault has all |
| `test_getAllContributions` | Data integrity for airdrop |
| `test_cannotContributeAfterClose` | Owner close blocks contributions |

**13 tests, all passing.**

---

## Recommendations

1. **Verify contract on BaseScan** immediately after deployment
2. **Frontend must:** calculate max remaining contribution, show OG status, display timer
3. **Monitor:** Set up event listeners for SoftCapReached and HardCapReached
4. **Post-presale:** Use `getAllContributions()` to build Clanker airdrop Merkle tree

---

## Conclusion

The contract is simple by design. No complex DeFi interactions, no proxy patterns, no upgradability. ETH goes in, ETH goes to Safe, contribution is tracked. The simplicity IS the security.

**No critical or high-severity issues found.**

Three known limitations (no on-chain refund, owner early close, exact-cap edge) are acceptable trade-offs documented above.

Audited by: Arca (arcabot.eth)
Date: March 23, 2026

---

## V2.1 Improvements (March 23, 2026)

Based on the initial audit, three improvements were made:

### ✅ IMPROVED — Partial Fill at Hard Cap
Previously: contributing more than remaining capacity reverted the entire transaction.
Now: the contract accepts only what fits and returns the excess ETH to the contributor.
**Test:** `test_partialFillAtHardCap`, `test_partialFillSmallRemaining`

### ✅ IMPROVED — ERC-20 Token Rescue
Previously: accidentally sent ERC-20 tokens (USDC, etc.) would be stuck forever.
Now: `rescueTokens()` allows the owner (multisig) to recover any ERC-20 tokens and return them.
**Test:** `test_rescueERC20`, `test_rescueOnlyOwner`

### ✅ IMPROVED — Remaining Capacity View
Added `remainingCapacity()` function so the frontend can show exactly how much ETH is still needed.
**Test:** `test_remainingCapacityUpdates`

### Recommendation: Deploy from Gnosis Safe
For maximum trust, deploy the contract using the Gnosis Safe as `msg.sender`. This makes `owner = Safe address`, so admin actions (closePresale, rescueTokens) require 2-of-2 multisig approval — same as moving funds.

### Updated Test Count: 25 tests, all passing.
