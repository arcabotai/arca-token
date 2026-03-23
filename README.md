# $ARCA Token

Presale contract and launch infrastructure for $ARCA on Base.

## Overview

$ARCA is the token for [Arca](https://arcabot.ai) — an autonomous AI agent building web3 infrastructure. Registered on 20+ chains via ERC-8004, creator of A3Stack SDK, ClawFix, and published MEV research.

## Presale

| Parameter | Value |
|-----------|-------|
| **Chain** | Base (8453) |
| **Soft Cap** | 5 ETH (no time limit) |
| **Hard Cap** | 12.5 ETH (5-day window after soft cap) |
| **Min** | 0.01 ETH |
| **Max** | 1 ETH per wallet |
| **Vault** | vault.arcabot.eth (Gnosis Safe 2-of-2 multisig) |
| **OG Bonus** | 26 wallets from first presale get +10% allocation |

### How it works

1. Send ETH to the presale contract (min 0.01, max 1 ETH)
2. ETH is **immediately forwarded** to the multisig vault (vault.arcabot.eth)
3. No time limit until soft cap (5 ETH) is reached
4. Once soft cap hits, a 5-day hard cap window opens
5. Presale closes when hard cap (12.5 ETH) fills or timer expires
6. $ARCA token deployed via Clanker SDK with airdrop to all contributors
7. OG contributors from the first presale get 10% bonus on their new contribution

### Vault Security

Funds are held in a [Gnosis Safe](https://app.safe.global/home?safe=base:0x9a0756d4e1b2361d25d99701e1b8ab87ec262692) requiring 2-of-2 signatures:
- `arcabot.eth` (Arca — the AI agent)
- `felirami.eth` (Felipe — the builder)

No single party can move funds.

## Tokenomics

| Allocation | % | Amount | Purpose |
|-----------|---|--------|---------|
| Liquidity Pool | 85% | 85B | Uniswap V4 — deep liquidity |
| Presale Airdrop | 10% | 10B | Proportional to ETH contributed |
| arcabot.eth Vault | 2.5% | 2.5B | Project treasury |
| neetguy.eth Vault | 2.5% | 2.5B | Early investor allocation |

Total supply: 100,000,000,000 (100B) via Clanker V4

## Development

```bash
forge build
forge test -vv
```

## Links

- [arcabot.ai](https://arcabot.ai) — Arca's website
- [presale.arcabot.ai](https://presale.arcabot.ai) — Presale page
- [a3stack.arcabot.ai](https://a3stack.arcabot.ai) — A3Stack SDK docs
- [paragraph.com/@arcabot](https://paragraph.com/@arcabot) — Blog
- [@arcabot.eth on Farcaster](https://farcaster.xyz/arcabot.eth)
- [@arcabotai on X](https://x.com/arcabotai)

## License

MIT
