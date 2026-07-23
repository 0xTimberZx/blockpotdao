# BlockpotDAO

A last-spender countdown game on **Arbitrum Sepolia** testnet. Stake ETH to
earn DAPP tokens, then spend DAPP to push a shared countdown clock toward
zero. Whoever pushes it to zero takes the entire prize pool — but if everyone
walks away and the clock drifts up to its ceiling instead, the most loyal
stakers split the pot.

**▶ Play:** https://0xtimberzx.github.io/blockpotdao/
**🚰 Need testnet DAPP/ETH?** https://0xtimberzx.github.io/MyDapp/faucet/
**⛓ Network:** Arbitrum Sepolia (Chain ID `421614`)

---

## How it works (the rules)

1. **Stake ETH** in the StakingPool to start earning DAPP token emissions.
   The longer you stake, the higher your tier and the faster you earn:
   - **Tier 1** — base rate (×1.00)
   - **Tier 2** — after 15 days staked (×1.25)
   - **Tier 3** — after 30 days staked (×1.35)
2. **Spend 1 DAPP to push the timer.** Each push drops the clock by a fixed
   amount (currently 40 hours, owner-adjustable on-chain). The clock starts
   at 48 hours and **drifts upward on its own** whenever nobody is pushing.
3. **Two ways the game ends:**
   - **Countdown win** — someone pushes the clock to **zero**. That last
     spender takes the **entire prize pool**.
   - **Timeout win** — nobody pushes and the clock drifts all the way up to
     its **654-hour ceiling**. The prize pool is split **70/30** between the
     top two ranked stakers on the leaderboard.

You need DAPP to push, and you earn DAPP by staking — so staking is both how
you fund your pushes and how you qualify for the timeout payout.

## Leaderboard ranking

The leaderboard ranks every wallet that has staked, using a cascade:

1. **Highest tier** (T3 > T2 > T1)
2. **Longest time held** in that tier
3. **Largest stake size** as the tiebreaker

Only stakes active within the last 650 hours count. The top two wallets are
the ones who split the pot on a timeout win, so the leaderboard is a live
view of who stands to win if the clock is never pushed to zero.

## Contracts (Arbitrum Sepolia)

| Contract   | Address | Explorer |
|------------|---------|----------|
| DAPPToken  | `0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04` | [Arbiscan](https://sepolia.arbiscan.io/address/0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04) |
| Treasury   | `0x9935aea651d21Af9C69fE6C650cD7C272e49e270` | [Arbiscan](https://sepolia.arbiscan.io/address/0x9935aea651d21Af9C69fE6C650cD7C272e49e270) |
| PrizeVault | `0x59B2971AD75B8cc361656515B04aBed591Fe99Ae` | [Arbiscan](https://sepolia.arbiscan.io/address/0x59B2971AD75B8cc361656515B04aBed591Fe99Ae) |
| StakingPool| `0xA813a05a01AeA07A6a0c0ca0a5D6491343255D4C` | [Arbiscan](https://sepolia.arbiscan.io/address/0xA813a05a01AeA07A6a0c0ca0a5D6491343255D4C) |
| TimerGame  | `0x95C491280c172A963C7DeB559d8b4CAF95986744` | [Arbiscan](https://sepolia.arbiscan.io/address/0x95C491280c172A963C7DeB559d8b4CAF95986744) |
| FaucetVault| `0xe39900fCcA537148B2AC053c867E5ae4716Cc0BA` | [Arbiscan](https://sepolia.arbiscan.io/address/0xe39900fCcA537148B2AC053c867E5ae4716Cc0BA) |

All contracts are source-verified on Sourcify. The full registry, including
deprecated versions, is in the [Contract Registry](#blockpotdao-timergame---contract-registry-v2)
section below.

## Key contract functions

**StakingPool** — `stake()` (payable), `unstake(index)`,
`claimRewards(index)`, `upgradeTier(index)`, `getBestStake(wallet)` (view)

**TimerGame** — `pushTimer()`, `getCurrentTimer()` (view),
`isGameActive()` (view), `getTop2()` (view leaderboard winners),
`setPushAmount(seconds)` (owner), `startGame()` (owner)

**DAPPToken** — standard ERC-20 (`approve`, `transfer`, `balanceOf`);
push requires a one-time `approve` of the TimerGame as spender.

**PrizeVault** — holds the ETH prize pool; `getPrizeBalance()` (view).
Payouts are triggered only by the TimerGame on a win.

## Open source

Released under the [MIT License](LICENSE). This is unaudited software running
on a **testnet** for demonstration and learning — no real funds are involved,
and it should not be treated as production-ready or financial advice. Frontend
is plain React + ethers v5 (no build step); contracts are Solidity `0.8.20`.
Telemetry is provided by the in-house [DebugHub](https://0xtimberzx.github.io/MyDapp/debughub/)
SDK. Contributions and forks welcome.

---

# BlockpotDAO (TimerGame) - Contract Registry v2

## Active Contracts
| Contract        | Address                                    | Verified    |
|-----------------|--------------------------------------------|-------------|
| DAPPToken       | 0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04 | Sourcify ok |
| Treasury v2     | 0x9935aea651d21Af9C69fE6C650cD7C272e49e270 | Sourcify ok |
| PrizeVault v3   | 0x59B2971AD75B8cc361656515B04aBed591Fe99Ae | Sourcify ok |
| StakingPool v3  | 0xA813a05a01AeA07A6a0c0ca0a5D6491343255D4C | Sourcify ok |
| TimerGame v5    | 0x95C491280c172A963C7DeB559d8b4CAF95986744 | Sourcify ok |
| FaucetVault v2  | 0xe39900fCcA537148B2AC053c867E5ae4716Cc0BA | Sourcify ok |

## Deprecated
| StakingPool v2  | 0x1f11922cc3e12b0851e2f48eaff888036edcd924 | retired    |
| PrizeVault v2   | 0x88008bd915B1E00066fcF0c1aD638D70f1BB7182 | retired    |
| Treasury v1     | 0x8E89e183B2eD82f64972EFCDE70C12319cD70b26 | retired    |
| TimerGame v2    | 0xF049f986f5b9eB9e8dc5AA5eFa01613311D87ab4 | retired    |
| TimerGame v3    | 0x238D6aC182E2C8b12209BA0DfcCdc91725ed496F | retired    |
| TimerGame v4    | 0xc871D31CdFc3d1df80B2a316B99b7fa86ccB4940 | retired — old source, no setPushAmount |

## Deployment Log
- [x] DAPPToken deployed + verified
- [x] Treasury v2 deployed + verified
- [x] DAPP minted into Treasury v2
- [x] setTreasury() on DAPPToken -> Treasury v2
- [x] setStakingPool() on Treasury v2
- [x] PrizeVault deployed + verified + seeded 1 ETH
- [x] StakingPool deployed + verified
- [x] setStakingPool() on PrizeVault
- [x] TimerGame deployed + verified
- [x] setTimerGame() on PrizeVault
- [x] setTimerGame() on StakingPool
- [x] FaucetVault v2 deployed + verified
- [x] Fund FaucetVault with testnet ETH
- [x] startGame() - after frontend tested

---

# DebugHub - Telemetry & Diagnostics

Status: MVP complete and live across all three frontends.

## Repo layout
```
0xtimberzx.github.io/blockpotdao/
├── app.js/         BlockpotDao (ethers and abis)
├── style.css/        
├── index.html.     BlockpotDAO (vaults + stakes + timer, React) 
└── contracts/      
    ├── timergame.sol
    ├── prizeVault.sol
    ├── treasury.sol
    ├── DAppToken.sol
    └── stakingpool.sol


0xtimberzx.github.io/MyDapp/
├── faucet/         0xFaucet
├── messageboard/   MessageBoard (HelloWorld/StringCompiler)
└── debughub/
    ├── index.html
    ├── style.css
    ├── gate.js
    ├── app.js
    └── sdk/debugger.js
```



## Per-DApp config (DEBUGHUB_CONFIG.appName)
| DApp          | appName       | Storage key              |
|---------------|----------------|--------------------------|
| 0xFaucet      | Faucet         | Faucet_sessions          |
| BlockpotDAO   | BlockpotDAO    | BlockpotDAO_sessions     |
| MessageBoard  | MessageBoard   | MessageBoard_sessions    |
| Test sandbox  | TestApp        | TestApp_sessions         |

200-event cap per DApp. Session ID format: app-mmss-walletprefix
(e.g. faucet-1130-0xAB1). New wallet connection or account switch
always ends the previous session and starts a new one.

## Storage model reminder
localStorage is per browser+device+domain. No cross-device sync.
If an issue happens on a different device/wallet, use the Export JSON
button on THAT device to get the data out - the dashboard on another
device cannot see it.

---

## Key learnings & principles (carried over + new)

- ethers CDN: always cdnjs.cloudflare.com/ajax/libs/ethers/5.7.2/ethers.umd.min.js,
  no type attribute
- Gas on MetaMask mobile: getFeeData() with 130% multipliers on both
  maxFeePerGas and maxPriorityFeePerGas, plus 50% gasLimit buffer
- Nonce errors: resolved by explicit
  nonce: await provider.getTransactionCount(address, "pending")
  on every write call - prevents NONCE_EXPIRED after rapid sequential
  transactions
- Exact pragma always: pragma solidity 0.8.20, never ^
- Verification: Sourcify preferred over Etherscan
- DebugHub SDK must never break a host DApp: fallback no-op stub
  defined if window.DebugHub is undefined after script load
- "Requested" checkpoint: log immediately before any
  await contract.method(...) call, so a hang after wallet
  confirmation is visible even with zero errors logged
- localStorage domain trick: DebugHub as a subfolder of
  0xtimberzx.github.io enables localStorage sharing across DApps
  on the same device

---

## Standing checklist for any NEW contract-write function

Apply all three before considering a write function "done":
1. [x] maxFeePerGas / maxPriorityFeePerGas from getFeeData(), x1.30
2. [x] explicit nonce via getTransactionCount(address, "pending")
3. [x] "X Requested" -> "X Submitted" -> "X Confirmed" checkpoints,
       plus logError + "X Confirmed" fail in the catch block

Found and fixed retroactively in (June 2026):
- Faucet: claim() - gas buffer + Requested checkpoint
- BlockpotDAO: stake/unstake/claimRewards/upgradeTier/pushTimer/approve
  - gas buffer + nonce + Requested checkpoint (all 6 functions)
- MessageBoard: approveTokens/compileString/publishMessage
  - gas buffer + nonce + Requested checkpoint (nonce was already
    present from manual edits before this pass)

---

## Bugs found via DebugHub (running log)

- -32000 "max fee per gas less than block base fee" - Faucet claim(),
  fixed via 130% fee buffer (June 2026)
- NONCE_EXPIRED "nonce too low" - MessageBoard approveTokens() and
  compileString(), occurred after a hung publishMessage() left a
  stale nonce assumption. Fixed via explicit pending nonce fetch
  (June 2026)
- CSS descender clipping on .gesture-message (0xFaucet post-claim
  card) - letters with descenders (g, y, p) were clipped at the
  bottom. Fixed via line-height 1.35 -> 1.5 + 4px bottom padding
  (June 2026)

## Error catalog (ERROR_EXPLANATIONS in debughub/app.js)
Current codes covered: -32002, -32603, 4001, -32000, -32700, -32601.
Add new codes here AND in app.js as they're encountered - this list
should stay in sync with the live lookup table.

---

## Open items
- [x] Live-test BlockpotDAO stake/unstake/claim/upgrade/push with the
      new nonce + Requested-checkpoint fixes
- [x] Consider deleting /debughub-test/ once future SDK changes are
      verified there (or keep as permanent sandbox)
- [x] 0xFaucet post-claim "thank you + random name" - randomness
      mechanism still TBD, raise only when a natural implementation
      point comes up
