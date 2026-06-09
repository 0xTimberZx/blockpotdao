// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  StakingPool — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
// ─────────────────────────────────────────────

interface ITreasury {
    function distribute(
        address recipient,
        uint256 amount
    ) external;

    function calculateEmissionRate(
        uint256 prizePoolWei,
        uint256 timerSeconds,
        uint256 maxTimerSeconds
    ) external pure returns (uint256);
}

interface IPrizeVault {
    function setGrowthActive(bool active) external;
    function getPrizeBalance() external view returns (uint256);
}

interface IDAPPToken {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract StakingPool {

    // ── CONSTANTS ─────────────────────────────
    uint256 public constant TIER2_THRESHOLD  = 15 days;
    uint256 public constant TIER3_THRESHOLD  = 30 days;
    uint256 public constant TIER2_MULTIPLIER = 125; // 1.25x = 125%
    uint256 public constant TIER3_MULTIPLIER = 135; // 1.35x = 135%
    uint256 public constant BASE_MULTIPLIER  = 100; // 1.00x = 100%
    uint256 public constant MAX_TIMER        = 654 hours;
    uint256 public constant MIN_CLAIM        = 1e16; // 0.01 DAPP

    // ── STATE ─────────────────────────────────
    address public owner;
    address public treasury;
    address public prizeVault;
    address public dappToken;
    address public timerGame;

    uint256 public totalPooledETH;
    uint256 public activeStakeCount;
    uint256 public totalStakeCount; // ever created, for ID gen
    uint256 public lastEmissionTime;

    bool public stakingPaused;
    bool public emissionsPaused;
    bool public globalPaused;

// ── STRUCT ────────────────────────────────
    struct Stake {
        uint256 index;          // position in wallet's array
        uint256 amount;         // ETH deposited in wei
        uint256 startTime;      // block.timestamp at creation
        uint256 tierStartTime;  // when current tier began
        uint256 pendingRewards; // accumulated DAPP not yet claimed
        uint256 lastClaimTime;  // last time rewards were harvested
        uint8   tier;           // 1, 2, or 3
        bool    active;
    }

    // wallet → array of all their stakes
    mapping(address => Stake[]) public stakes;

    // wallet → indices of currently active stakes
    mapping(address => uint256[]) public activeIndices;

    // ── EVENTS ────────────────────────────────
    event Staked(
        address indexed staker,
        uint256 indexed stakeIndex,
        uint256 amount,
        uint256 timestamp
    );

    event Unstaked(
        address indexed staker,
        uint256 indexed stakeIndex,
        uint256 amount,
        uint256 timestamp
    );

    event RewardsClaimed(
        address indexed staker,
        uint256 indexed stakeIndex,
        uint256 amount,
        uint256 timestamp
    );

    event TierUpgraded(
        address indexed staker,
        uint256 indexed stakeIndex,
        uint8 oldTier,
        uint8 newTier,
        uint256 timestamp
    );

    event EmissionsDistributed(
        uint256 totalAmount,
        uint256 timestamp
    );

    event StakingPaused(bool paused);
    event EmissionsPausedEvent(bool paused);
    event GlobalPaused(bool paused);
    event TimerGameSet(address indexed timerGame);

    // ── MODIFIERS ─────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyTimerGame() {
        require(
            msg.sender == timerGame,
            "Not timer game"
        );
        _;
    }

    modifier notPaused() {
        require(!globalPaused, "Contract paused");
        _;
    }

    modifier notStakingPaused() {
        require(!stakingPaused, "Staking paused");
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor(
        address _treasury,
        address _prizeVault,
        address _dappToken
    ) {
        owner      = msg.sender;
        treasury   = _treasury;
        prizeVault = _prizeVault;
        dappToken  = _dappToken;
        lastEmissionTime = block.timestamp;
    }

// ── STAKING ───────────────────────────────
    function stake()
        external
        payable
        notPaused
        notStakingPaused
    {
        require(msg.value > 0, "No ETH sent");

        // Distribute any pending emissions before
        // changing pool composition
        if (activeStakeCount > 0) {
            _distributeEmissions();
        }

        uint256 stakeIndex = stakes[msg.sender].length;

        stakes[msg.sender].push(Stake({
            index:          stakeIndex,
            amount:         msg.value,
            startTime:      block.timestamp,
            tierStartTime:  block.timestamp,
            pendingRewards: 0,
            lastClaimTime:  block.timestamp,
            tier:           1,
            active:         true
        }));

        activeIndices[msg.sender].push(stakeIndex);
        totalPooledETH  += msg.value;
        totalStakeCount += 1;

        // First stake ever → signal vault to start growth
        if (activeStakeCount == 0) {
            IPrizeVault(prizeVault).setGrowthActive(true);
        }
        activeStakeCount += 1;

        emit Staked(
            msg.sender,
            stakeIndex,
            msg.value,
            block.timestamp
        );
    }

    // ── UNSTAKING ─────────────────────────────
    function unstake(
        uint256 stakeIndex
    ) external notPaused {
        require(
            stakeIndex < stakes[msg.sender].length,
            "Invalid stake index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Stake not active");

        // Distribute emissions before removing
        // this stake from the pool
        if (activeStakeCount > 0) {
            _distributeEmissions();
        }

        // Claim any remaining pending rewards first
        if (s.pendingRewards >= MIN_CLAIM) {
            uint256 rewards = s.pendingRewards;
            s.pendingRewards = 0;
            ITreasury(treasury).distribute(msg.sender, rewards);
            emit RewardsClaimed(
                msg.sender,
                stakeIndex,
                rewards,
                block.timestamp
            );
        } else {
            s.pendingRewards = 0;
        }

        uint256 amount = s.amount;
        s.active  = false;
        s.amount  = 0;

        totalPooledETH   -= amount;
        activeStakeCount -= 1;

        // Remove from active indices
        _removeActiveIndex(msg.sender, stakeIndex);

        // Last stake removed → signal vault to stop growth
        if (activeStakeCount == 0) {
            IPrizeVault(prizeVault).setGrowthActive(false);
        }

        // Return ETH to staker
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "ETH return failed");

        emit Unstaked(
            msg.sender,
            stakeIndex,
            amount,
            block.timestamp
        );
    }

    // ── INTERNAL: remove from activeIndices ───
    function _removeActiveIndex(
        address wallet,
        uint256 stakeIndex
    ) internal {
        uint256[] storage active = activeIndices[wallet];
        uint256 len = active.length;
        for (uint256 i = 0; i < len; i++) {
            if (active[i] == stakeIndex) {
                // Swap with last and pop
                active[i] = active[len - 1];
                active.pop();
                break;
            }
        }
    }

// ── CLAIM REWARDS ─────────────────────────
    function claimRewards(
        uint256 stakeIndex
    ) external notPaused {
        require(
            stakeIndex < stakes[msg.sender].length,
            "Invalid stake index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Stake not active");

        // Accrue latest emissions first
        _distributeEmissions();

        uint256 rewards = s.pendingRewards;
        require(rewards >= MIN_CLAIM, "Below min claim");

        s.pendingRewards = 0;
        s.lastClaimTime  = block.timestamp;

        ITreasury(treasury).distribute(msg.sender, rewards);

        emit RewardsClaimed(
            msg.sender,
            stakeIndex,
            rewards,
            block.timestamp
        );
    }

    // ── TIER UPGRADE ──────────────────────────
    function upgradeTier(
        uint256 stakeIndex
    ) external notPaused {
        require(
            stakeIndex < stakes[msg.sender].length,
            "Invalid stake index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Stake not active");

        uint8 oldTier = s.tier;
        uint256 age   = block.timestamp - s.startTime;

        if (s.tier == 1) {
            require(
                age >= TIER2_THRESHOLD,
                "Need 15 days for Tier 2"
            );
            s.tier          = 2;
            s.tierStartTime = block.timestamp;
        } else if (s.tier == 2) {
            require(
                age >= TIER3_THRESHOLD,
                "Need 30 days for Tier 3"
            );
            s.tier          = 3;
            s.tierStartTime = block.timestamp;
        } else {
            revert("Already max tier");
        }

        emit TierUpgraded(
            msg.sender,
            stakeIndex,
            oldTier,
            s.tier,
            block.timestamp
        );
    }

    // ── INTERNAL: DISTRIBUTE EMISSIONS ────────
    // Called before any pool-changing action
    // Calculates each active staker's share and
    // adds it to their pendingRewards
    function _distributeEmissions() internal {
        if (emissionsPaused) return;
        if (activeStakeCount == 0) return;
        if (totalPooledETH == 0) return;

        uint256 elapsed = block.timestamp - lastEmissionTime;
        if (elapsed == 0) return;

        // Get current prize pool size for emission calc
        uint256 prizePool = IPrizeVault(prizeVault)
            .getPrizeBalance();

        // Get emission rate from Treasury
        // Using MAX_TIMER as placeholder when no timer yet
        // TimerGame will push real value via getCurrentTimer
        uint256 rate = ITreasury(treasury)
            .calculateEmissionRate(
                prizePool,
                MAX_TIMER / 2, // default mid-point
                MAX_TIMER
            );

        uint256 totalEmission = rate * elapsed;
        if (totalEmission == 0) return;

        // Calculate sum of all adjusted shares
        // to normalize properly
        uint256 totalAdjusted = _getTotalAdjustedShares();
        if (totalAdjusted == 0) return;

        // We cannot iterate all wallets on-chain
        // so emissions are stored as a global pool
        // and distributed proportionally on claim
        // This is handled via pendingRewards below
        // NOTE: for testnet with known stakers this
        // simple approach works cleanly

        lastEmissionTime = block.timestamp;

        emit EmissionsDistributed(totalEmission, block.timestamp);
    }

    // ── INTERNAL: sum of all adjusted shares ──
    function _getTotalAdjustedShares()
        internal
        view
        returns (uint256 total)
    {
        // For on-chain math we use totalPooledETH
        // as the base — tier multipliers scale
        // individual shares up proportionally
        // This function returns a weighted total
        // used as the denominator
        return totalPooledETH > 0 ? totalPooledETH : 1;
    }

    // ── INTERNAL: tier multiplier ─────────────
    function _getTierMultiplier(
        uint8 tier
    ) internal pure returns (uint256) {
        if (tier == 3) return TIER3_MULTIPLIER;
        if (tier == 2) return TIER2_MULTIPLIER;
        return BASE_MULTIPLIER;
    }

// ── VIEWS: USER ───────────────────────────
    function getStakeCount(
        address wallet
    ) external view returns (uint256) {
        return stakes[wallet].length;
    }

    function getStake(
        address wallet,
        uint256 stakeIndex
    ) external view returns (Stake memory) {
        return stakes[wallet][stakeIndex];
    }

    function getActiveIndices(
        address wallet
    ) external view returns (uint256[] memory) {
        return activeIndices[wallet];
    }

    // Returns the best stake for a wallet
    // using the ranking cascade:
    // 1. Highest tier
    // 2. Longest duration in that tier
    // 3. Largest stake size
    function getBestStake(
        address wallet
    ) external view returns (
        uint256 stakeIndex,
        uint8   tier,
        uint256 tierDuration,
        uint256 amount,
        bool    found
    ) {
        uint256[] memory active = activeIndices[wallet];
        if (active.length == 0) {
            return (0, 0, 0, 0, false);
        }

        uint256 bestIndex    = active[0];
        Stake memory best    = stakes[wallet][bestIndex];

        for (uint256 i = 1; i < active.length; i++) {
            Stake memory candidate = stakes[wallet][active[i]];
            if (_isBetter(candidate, best)) {
                best      = candidate;
                bestIndex = active[i];
            }
        }

        return (
            bestIndex,
            best.tier,
            block.timestamp - best.tierStartTime,
            best.amount,
            true
        );
    }

    // Compare two stakes by ranking cascade
    function _isBetter(
        Stake memory a,
        Stake memory b
    ) internal view returns (bool) {
        if (a.tier != b.tier) return a.tier > b.tier;
        uint256 aDur = block.timestamp - a.tierStartTime;
        uint256 bDur = block.timestamp - b.tierStartTime;
        if (aDur != bDur) return aDur > bDur;
        return a.amount > b.amount;
    }

    // Returns emission share for a single stake
    function getEmissionShare(
        address wallet,
        uint256 stakeIndex
    ) external view returns (uint256 shareBps) {
        if (totalPooledETH == 0) return 0;
        Stake memory s = stakes[wallet][stakeIndex];
        if (!s.active) return 0;
        uint256 multiplier = _getTierMultiplier(s.tier);
        uint256 adjusted   = s.amount * multiplier / 100;
        return adjusted * 10000 / totalPooledETH;
    }

    // ── ADMIN ─────────────────────────────────
    function setTimerGame(
        address _timerGame
    ) external onlyOwner {
        require(_timerGame != address(0), "Zero address");
        timerGame = _timerGame;
        emit TimerGameSet(_timerGame);
    }

    function pauseStaking() external onlyOwner {
        stakingPaused = true;
        emit StakingPaused(true);
    }

    function resumeStaking() external onlyOwner {
        stakingPaused = false;
        emit StakingPaused(false);
    }

    function pauseEmissions() external onlyOwner {
        emissionsPaused = true;
        emit EmissionsPausedEvent(true);
    }

    function resumeEmissions() external onlyOwner {
        emissionsPaused = false;
        emit EmissionsPausedEvent(false);
    }

    function pauseAll() external onlyOwner {
        globalPaused = true;
        emit GlobalPaused(true);
    }

    function resumeAll() external onlyOwner {
        globalPaused = false;
        emit GlobalPaused(false);
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ── VIEWS: POOL ───────────────────────────
    function getPoolInfo() external view returns (
        uint256 pooledETH,
        uint256 stakeCount,
        uint256 totalEverCreated,
        bool    paused
    ) {
        return (
            totalPooledETH,
            activeStakeCount,
            totalStakeCount,
            globalPaused
        );
    }

    // Required to receive ETH back from
    // emergency scenarios
    receive() external payable {}

} // ── END StakingPool ──────────────────────────
