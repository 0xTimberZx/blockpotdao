# BlockpotDAO — Contract Registry

## Network
Chain:    Arbitrum Sepolia
Chain ID: 421614
Compiler: solc 0.8.20
Optimizer: OFF

## Contracts
| Contract    | Address                                    | Verified    |
|-------------|--------------------------------------------|-------------|
| DAPPToken   | 0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04 | ✅ Sourcify |
| Treasury    | 0x8E89e183B2eD82f64972EFCDE70C12319cD70b26 | ✅ Sourcify |
| PrizeVault  | 0xB563B77Bc55B2E5A0f3f1371f427AE383cfE79Ef | ✅ Sourcify |
| StakingPool | 0x2a3517aC88C78FAbEC3a918e509dd77156413669 | ✅ Sourcify |
| TimerGame   | 0xB1d11f509DaB1B8838f2d0B61eF2c6C82551678f | ✅ Sourcify |

## Deployment Log
- [x] DAPPToken deployed + verified ✅
- [x] Treasury deployed + verified ✅
- [x] 1,000,000 DAPP transferred to Treasury ✅
- [x] setTreasury() called on DAPPToken ✅
- [x] PrizeVault deployed + verified ✅
- [x] fund() called with 1 ETH ✅
- [x] StakingPool deployed + verified ✅
- [x] setStakingPool() called on Treasury ✅
- [x] setStakingPool() called on PrizeVault ✅
- [x] TimerGame deployed + verified ✅
- [ ] setTimerGame() on PrizeVault
- [ ] setTimerGame() on StakingPool
- [ ] Approve DAPP max allowance for TimerGame
- [ ] startGame() — DO LAST after frontend tested


DONE ✅  All 5 contracts deployed + verified
DONE ✅  All cross-contract authorizations wired
TODO     3 final wiring actions above
TODO     Frontend build — CDN React
TODO     Test with 3 wallets before startGame()
TODO     startGame() — the point of no return
