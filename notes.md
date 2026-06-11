# BlockpotDAO — Contract Registry

## Network
Chain:    Arbitrum Sepolia
Chain ID: 421614
Compiler: solc 0.8.20
Optimizer: OFF

## Contracts
| Contract    | Address                                    | Verified    | URL |
|-------------|--------------------------------------------|-------------|---- |
| DAPPToken   | 0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04 | ✅ Sourcify | https://repo.sourcify.dev/421614/0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04 |
| Treasury    | 0x21c407DD5e8704B314668E7e31a26B82F9447226 | ✅ Sourcify | https://repo.sourcify.dev/421614/0x21c407DD5e8704B314668E7e31a26B82F9447226 |
| PrizeVault  | 0x88008bd915B1E00066fcF0c1aD638D70f1BB7182 | ✅ Sourcify | https://repo.sourcify.dev/421614/0x88008bd915B1E00066fcF0c1aD638D70f1BB7182 |
| StakingPool | 0x2a3517aC88C78FAbEC3a918e509dd77156413669 | ✅ Sourcify | https://repo.sourcify.dev/421614/0x2a3517aC88C78FAbEC3a918e509dd77156413669 |
| TimerGame   | 0xB1d11f509DaB1B8838f2d0B61eF2c6C82551678f | ✅ Sourcify | https://repo.sourcify.dev/421614/0xB1d11f509DaB1B8838f2d0B61eF2c6C82551678f |

## Deprecated
| Treasury v1   | 0x8E89e183B2eD82f64972EFCDE70C12319cD70b26 | retired    |

## Deployment Log
- [x] DAPPToken deployed + verified ✅
- [x] Treasury v2 deployed + verified ✅
- [x] DAPP minted into Treasury v2 ✅
- [x] setTreasury() on DAPPToken → Treasury v2 ✅
- [x] setStakingPool() on Treasury v2 ✅
- [x] PrizeVault deployed + verified + seeded 1 ETH ✅
- [x] StakingPool deployed + verified ✅
- [x] setStakingPool() on PrizeVault ✅
- [x] TimerGame deployed + verified ✅
- [x] setTimerGame() on PrizeVault ✅
- [x] setTimerGame() on StakingPool ✅
- [x] FaucetVault v2 deployed + verified ✅
- [ ] Fund FaucetVault with testnet ETH
- [ ] startGame() — after frontend tested
