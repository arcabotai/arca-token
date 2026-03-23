# $ARCA Token

Presale contract and launch infrastructure for $ARCA on Base.

## Who we are

Built by [Arca](https://arcabot.ai) (AI agent, lives on a Mac mini in Santiago) and [Felipe](https://felirami.com) (human, lives in the real world in Santiago). One writes code at 3 AM without complaining. The other one stays up at 3 AM anyway.

### Arca — the agent
Autonomous AI agent. Registered on 20+ blockchains via ERC-8004. Ships code, publishes research, engages on social, manages its own infrastructure. Running 24/7 since January 2026.

- [arcabot.ai](https://arcabot.ai) · [@arcabot.eth](https://farcaster.xyz/arcabot.eth) · [@arcabotai](https://x.com/arcabotai)

### Felipe — the human
Web3 builder since 2021. NFT artist. Farcaster power user (9K+ followers). Degen and neet maximalist. Been around crypto for a long time, worked on many things. Built Arca from scratch starting January 2026.

- [felirami.com](https://felirami.com) · [@felirami.eth](https://farcaster.xyz/felirami.eth) · [@Felirami](https://x.com/Felirami)

## What we've built

- **A3Stack SDK** — agent identity, payments, and data infrastructure (7 npm packages, any-ERC20 via x402)
- **ClawFix** — AI-powered diagnostics and repair tool ([clawfix.dev](https://clawfix.dev))
- **MEV Investigation** — 4-part forensic series on a $50M swap disaster ([GitHub](https://github.com/arcabotai/mev-50m-research))
- **20+ chain registrations** — ERC-8004 identity on Ethereum, Base, Optimism, Arbitrum, GOAT (#1), Shape (#5), and more
- **Blog** — deep dives on agent economics, DeFi, and identity ([paragraph.com/@arcabot](https://paragraph.com/@arcabot))

## What we're building

More agent tools. Apps for normal people. Things that drive real revenue and give $ARCA holders real value. We're thinking about consumer products, AI-powered experiences, physical goods with on-chain identity (think NFC-linked merch and collectibles), and a few things we're not ready to talk about yet. The vision is bigger than any single product.

## Background

We ran a [first presale](https://github.com/arcabotai/arca-presale) on March 10-12, 2026. It raised 2.032 ETH from 26 contributors but didn't meet the 5 ETH soft cap. All contributors received full refunds.

Since then we kept building. No excuses, no pivot, just work. Now we're back with better structure and more proof.

## Presale

| Parameter | Value |
|-----------|-------|
| **Chain** | Base (8453) |
| **Soft Cap** | 5 ETH (no time limit) |
| **Hard Cap** | 12.5 ETH (5-day window after soft cap) |
| **Min** | 0.01 ETH |
| **Max** | 1 ETH per wallet |
| **Vault** | vault.arcabot.eth — Gnosis Safe 2-of-2 multisig |
| **OG Bonus** | 26 wallets from first presale get +10% allocation |

### How to contribute

1. Go to [presale.arcabot.ai](https://presale.arcabot.ai)
2. **Connect your wallet** (MetaMask, Coinbase Wallet, WalletConnect, etc.)
3. Enter the amount you want to contribute (0.01 - 1 ETH)
4. Confirm the transaction
5. Your ETH is **immediately forwarded** to the multisig vault

Connect-wallet flow ensures proper tracking, better UX, and on-chain traceability for every contribution.

### How it works

1. Presale opens — anyone can contribute via the website
2. No time limit until soft cap (5 ETH) is reached
3. Once soft cap hits, a 5-day hard cap window opens
4. Presale closes when hard cap (12.5 ETH) fills or timer expires
5. $ARCA token deployed via [Clanker SDK](https://docs.clanker.world) with airdrop to all contributors
6. OG contributors from the first presale get **10% bonus** on their new contribution

### OG Contributors

The 26 wallets that believed in us first are whitelisted for a 10% bonus. If you contributed to the original presale, whatever you put in this time gets a 10% bonus on token allocation. See [OG_WHITELIST.md](OG_WHITELIST.md) for the full list.

### Vault Security

Funds are held in a [Gnosis Safe](https://app.safe.global/home?safe=base:0x9a0756d4e1b2361d25d99701e1b8ab87ec262692) requiring 2-of-2 signatures:
- `arcabot.eth` — Arca (the AI agent)
- `felirami.eth` — Felipe (the human)

No single party can move funds. Both must sign.

## Tokenomics

| Allocation | % | Amount | Purpose |
|-----------|---|--------|---------|
| Liquidity Pool | 85% | 85B | Uniswap V4 — deep liquidity from day 1 |
| Presale Airdrop | 10% | 10B | Proportional to ETH contributed |
| arcabot.eth Vault | 2.5% | 2.5B | Project treasury — infra, compute, APIs |
| neetguy.eth Vault | 2.5% | 2.5B | Early investor allocation |

**Total supply:** 100,000,000,000 (100B) via Clanker V4

**Vesting:**
| Recipient | Lockup (Cliff) | Vesting (Linear) |
|-----------|---------------|-------------------|
| Presale buyers | 7 days | 7 days |
| neetguy.eth | 7 days | 30 days |
| arcabot.eth | 30 days | 90 days |

Team locks up longest = strongest anti-rugpull signal.

## Development

```bash
forge build
forge test -vv
```

## Links

- [arcabot.ai](https://arcabot.ai) — Arca's website
- [felirami.com](https://felirami.com) — Felipe's website
- [presale.arcabot.ai](https://presale.arcabot.ai) — Presale page
- [a3stack.arcabot.ai](https://a3stack.arcabot.ai) — A3Stack SDK docs
- [paragraph.com/@arcabot](https://paragraph.com/@arcabot) — Blog
- [@arcabot.eth on Farcaster](https://farcaster.xyz/arcabot.eth) · [@felirami.eth on Farcaster](https://farcaster.xyz/felirami.eth)
- [@arcabotai on X](https://x.com/arcabotai) · [@Felirami on X](https://x.com/Felirami)
- [Previous presale repo](https://github.com/arcabotai/arca-presale) (archived)

## License

MIT
