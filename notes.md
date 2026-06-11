# BlockpotDAO — Contract Registry v2

## Active Contracts
| Contract        | Address                                    | Verified    |
|-----------------|--------------------------------------------|-------------|
| DAPPToken       | 0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04 | ✅ Sourcify |
| Treasury v2     | 0x9935aea651d21Af9C69fE6C650cD7C272e49e270 | ✅ Sourcify |
| PrizeVault v2   | 0x88008bd915B1E00066fcF0c1aD638D70f1BB7182 | ✅ Sourcify |
| StakingPool v2  | 0x1f11922cc3e12b0851e2f48eaff888036edcd924 | ✅ Sourcify |
| TimerGame       | 0xB1d11f509DaB1B8838f2d0B61eF2c6C82551678f | ✅ Sourcify |
| FaucetVault v2  | 0xe39900fCcA537148B2AC053c867E5ae4716Cc0BA | ✅ Sourcify |

## Deprecated
| StakingPool v1  | 0x2a3517aC88C78FAbEC3a918e509dd77156413669 | retired    |
| PrizeVault v1   | 0xB563B77Bc55B2E5A0f3f1371f427AE383cfE79Ef | retired    |
| Treasury v1     | 0x8E89e183B2eD82f64972EFCDE70C12319cD70b26 | retired    |

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
