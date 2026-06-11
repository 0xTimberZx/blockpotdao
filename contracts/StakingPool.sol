// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  StakingPool — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
//  Version  : 2 — Emissions write to state
// ─────────────────────────────────────────────

interface ITreasury {
    function distribute(
        address recipient,
        uint256 amount
    ) external;

    function calculateEmissionRate(
        uint256 prizePoolWei
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

interface ITimerGame {
    function getCurrentTimer()
        external view returns (uint256);
    function isGameActive()
        external view returns (bool);
}

contract StakingPool {

    // ── CONSTANTS ─────────────────────────────
    uint256 public constant TIER2_THRESHOLD  = 15 days;
    uint256 public constant TIER3_THRESHOLD  = 30 days;
    uint256 public constant TIER2_MULTIPLIER = 125;
    uint256 public constant TIER3_MULTIPLIER = 135;
    uint256 public constant BASE_MULTIPLIER  = 100;
    uint256 public constant MAX_TIMER        = 654 hours;
    uint256 public constant MIN_CLAIM        = 1e16;

    // ── STATE ─────────────────────────────────
    address public owner;
    address public treasury;
    address public prizeVault;
    address public dappToken;
    address public timerGame;

    uint256 public totalPooledETH;
    uint256 public activeStakeCount;
    uint256 public totalStakeCount;
    uint256 public lastEmissionTime;

    bool public stakingPaused;
    bool public emissionsPaused;
    bool public globalPaused;
// ── STRUCT ────────────────────────────────
    struct Stake {
        uint256 index;
        uint256 amount;
        uint256 startTime;
        uint256 tierStartTime;
        uint256 pendingRewards;
        uint256 lastClaimTime;
        uint8   tier;
        bool    active;
    }

    mapping(address => Stake[]) public stakes;
    mapping(address => uint256[]) public activeIndices;

    // All wallets that have ever staked
    // Used for emission distribution
    address[] public stakerList;
    mapping(address => bool) public isStaker;

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

    event EmissionsAccrued(
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
        owner            = msg.sender;
        treasury         = _treasury;
        prizeVault       = _prizeVault;
        dappToken        = _dappToken;
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

        // Accrue emissions before pool changes
        _accrueEmissions();

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
        totalPooledETH   += msg.value;
        totalStakeCount  += 1;
        activeStakeCount += 1;

        // Register staker for emission tracking
        if (!isStaker[msg.sender]) {
            isStaker[msg.sender] = true;
            stakerList.push(msg.sender);
        }

        // First stake → signal vault to start growth
        if (activeStakeCount == 1) {
            IPrizeVault(prizeVault).setGrowthActive(true);
        }

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
            "Invalid index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Not active");

        // Accrue before removing from pool
        _accrueEmissions();

        // Auto-claim any pending rewards
        uint256 rewards = s.pendingRewards;
        if (rewards >= MIN_CLAIM) {
            s.pendingRewards = 0;
            ITreasury(treasury).distribute(
                msg.sender, rewards
            );
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
        s.active = false;
        s.amount = 0;

        totalPooledETH   -= amount;
        activeStakeCount -= 1;

        _removeActiveIndex(msg.sender, stakeIndex);

        // Last stake removed → stop vault growth
        if (activeStakeCount == 0) {
            IPrizeVault(prizeVault).setGrowthActive(false);
        }

        (bool sent, ) = payable(msg.sender).call{
            value: amount
        }("");
        require(sent, "ETH return failed");

        emit Unstaked(
            msg.sender,
            stakeIndex,
            amount,
            block.timestamp
        );
    }

    // ── INTERNAL: remove active index ─────────
    function _removeActiveIndex(
        address wallet,
        uint256 stakeIndex
    ) internal {
        uint256[] storage active = activeIndices[wallet];
        uint256 len = active.length;
        for (uint256 i = 0; i < len; i++) {
            if (active[i] == stakeIndex) {
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
            "Invalid index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Not active");

        // Accrue latest emissions first
        _accrueEmissions();

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
            "Invalid index"
        );
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(s.active, "Not active");

        uint8 oldTier  = s.tier;
        uint256 age    = block.timestamp - s.startTime;

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

    // ── CORE: ACCRUE EMISSIONS ─────────────────
    // This is the fixed version — actually writes
    // earned tokens to each staker's pendingRewards
    function _accrueEmissions() internal {
        if (emissionsPaused) return;
        if (activeStakeCount == 0) return;
        if (totalPooledETH == 0) return;

        uint256 elapsed = block.timestamp - lastEmissionTime;
        if (elapsed == 0) return;

        // Get current prize pool for emission rate
        uint256 prizePool = IPrizeVault(prizeVault)
            .getPrizeBalance();
        if (prizePool == 0) return;

        // Get emission rate from Treasury
        // Rate = tokens per second based on prize pool
        uint256 rate = ITreasury(treasury)
            .calculateEmissionRate(prizePool);

        uint256 totalEmission = rate * elapsed;
        if (totalEmission == 0) return;

        // Calculate weighted total for share math
        // Accounts for tier multipliers
        uint256 weightedTotal = _getWeightedTotal();
        if (weightedTotal == 0) return;

        // Distribute proportional share to every
        // active stake across all registered stakers
        uint256 distributed = 0;
        uint256 stakerCount  = stakerList.length;

        for (uint256 i = 0; i < stakerCount; i++) {
            address wallet = stakerList[i];
            uint256[] memory active = activeIndices[wallet];
            uint256 activeLen = active.length;

            for (uint256 j = 0; j < activeLen; j++) {
                Stake storage s = stakes[wallet][active[j]];
                if (!s.active || s.amount == 0) continue;

                uint256 multiplier = _getTierMultiplier(s.tier);
                uint256 weighted   = s.amount * multiplier / 100;

                // Share = weighted / weightedTotal
                // Reward = totalEmission * share
                uint256 reward =
                    totalEmission * weighted / weightedTotal;

                s.pendingRewards += reward;
                distributed      += reward;
            }
        }

        lastEmissionTime = block.timestamp;

        emit EmissionsAccrued(distributed, block.timestamp);
    }

    // ── INTERNAL: weighted pool total ─────────
    function _getWeightedTotal()
        internal
        view
        returns (uint256 total)
    {
        uint256 stakerCount = stakerList.length;
        for (uint256 i = 0; i < stakerCount; i++) {
            address wallet = stakerList[i];
            uint256[] memory active = activeIndices[wallet];
            for (uint256 j = 0; j < active.length; j++) {
                Stake storage s = stakes[wallet][active[j]];
                if (!s.active || s.amount == 0) continue;
                uint256 multiplier = _getTierMultiplier(s.tier);
                total += s.amount * multiplier / 100;
            }
        }
        return total;
    }

    // ── INTERNAL: tier multiplier ─────────────
    function _getTierMultiplier(
        uint8 tier
    ) internal pure returns (uint256) {
        if (tier == 3) return TIER3_MULTIPLIER;
        if (tier == 2) return TIER2_MULTIPLIER;
        return BASE_MULTIPLIER;
    }

    // ── PUBLIC: manual accrual trigger ────────
    // Anyone can call to force emission snapshot
    function accrueEmissions() external notPaused {
        _accrueEmissions();
    }

// ── VIEWS ─────────────────────────────────
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

        uint256 bestIndex = active[0];
        Stake memory best = stakes[wallet][bestIndex];

        for (uint256 i = 1; i < active.length; i++) {
            Stake memory candidate =
                stakes[wallet][active[i]];
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

    function getPendingRewards(
        address wallet,
        uint256 stakeIndex
    ) external view returns (uint256) {
        return stakes[wallet][stakeIndex].pendingRewards;
    }

    function getPoolInfo() external view returns (
        uint256 pooledETH,
        uint256 stakeCount,
        uint256 totalEver,
        bool    paused
    ) {
        return (
            totalPooledETH,
            activeStakeCount,
            totalStakeCount,
            globalPaused
        );
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

    receive() external payable {}

} // ── END StakingPool v2 ────────────────────────
