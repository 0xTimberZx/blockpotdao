// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  PrizeVault — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
// ─────────────────────────────────────────────

contract PrizeVault {

    // ── STATE ─────────────────────────────────
    address public owner;
    address public stakingPool;
    address public timerGame;

    // Prize growth config
    uint256 public growthIntervalSeconds = 216000; // 60 hours
    uint256 public lastGrowthTime;
    bool    public growthActive;
    bool    public vaultPaused;
    bool    public gameEnded;

    // Growth rate bounds (percentage points)
    uint256 public constant GROWTH_MIN = 10;
    uint256 public constant GROWTH_MAX = 20;

    // Tracks prize balance separately from
    // any accidental ETH sent directly
    uint256 public prizeBalance;

    // ── EVENTS ────────────────────────────────
    event Funded(
        address indexed sender,
        uint256 amount
    );

    event GrowthApplied(
        uint256 oldBalance,
        uint256 newBalance,
        uint256 growthPercent
    );

    event GrowthActiveChanged(bool active);

    event WinnerPaid(
        address indexed winner,
        uint256 amount
    );

    event SplitPaid(
        address indexed first,
        uint256 firstAmount,
        address indexed second,
        uint256 secondAmount
    );

    event VaultPaused(bool paused);

    event StakingPoolSet(address indexed stakingPool);

    event TimerGameSet(address indexed timerGame);

    // ── MODIFIERS ─────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyStakingPool() {
        require(
            msg.sender == stakingPool,
            "Not staking pool"
        );
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
        require(!vaultPaused, "Vault paused");
        _;
    }

    modifier notEnded() {
        require(!gameEnded, "Game has ended");
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor() {
        owner = msg.sender;
        lastGrowthTime = block.timestamp;
    }

    // ── FUNDING ───────────────────────────────
    // Owner seeds the prize pot
    // Call this with ETH attached after deployment
    function fund() external payable onlyOwner notEnded {
        require(msg.value > 0, "No ETH sent");
        prizeBalance += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    // Anyone can add to prize balance
    // Used by FaucetVault 50/50 split
    function addToPrize() external payable {
        require(msg.value > 0, "No ETH sent");
        prizeBalance += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    // Safety receive — logs but does not
    // add to prizeBalance to keep accounting clean
    receive() external payable {
        prizeBalance += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    // ── GROWTH ────────────────────────────────
    // Anyone can call this after 60 hours
    // Growth only applies when growthActive == true
    // meaning at least 1 active stake exists
    function applyGrowth() external notPaused notEnded {
        require(growthActive, "Growth not active");
        require(
            block.timestamp >= lastGrowthTime + growthIntervalSeconds,
            "Too soon"
        );
        require(prizeBalance > 0, "Empty vault");

        // Pseudo-random growth between 10-20%
        // Safe for testnet — not suitable for mainnet
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    prizeBalance
                )
            )
        );
        uint256 growthPercent = GROWTH_MIN +
            (seed % (GROWTH_MAX - GROWTH_MIN + 1));

        uint256 oldBalance = prizeBalance;
        uint256 growthAmount = (prizeBalance * growthPercent) / 100;
        prizeBalance += growthAmount;
        lastGrowthTime = block.timestamp;

        emit GrowthApplied(oldBalance, prizeBalance, growthPercent);
    }

    // ── GROWTH CONTROL ────────────────────────
    // Called by StakingPool when stake count
    // crosses the 0↔1 threshold
    function setGrowthActive(
        bool active
    ) external onlyStakingPool {
        growthActive = active;
        emit GrowthActiveChanged(active);
    }

    // ── PRIZE DISTRIBUTION ────────────────────
    // Win condition A — timer hits 00:00:00
    // Last token spender takes everything
    function distributeAll(
        address winner
    ) external onlyTimerGame notPaused {
        require(winner != address(0), "Zero address");
        require(prizeBalance > 0, "Empty vault");

        uint256 payout = prizeBalance;
        prizeBalance = 0;
        gameEnded = true;

        (bool sent, ) = payable(winner).call{value: payout}("");
        require(sent, "Transfer failed");

        emit WinnerPaid(winner, payout);
    }

    // Win condition B — timer hits 654 hours
    // Top 2 stakers split 70/30
    function distributeSplit(
        address first,
        address second
    ) external onlyTimerGame notPaused {
        require(first != address(0), "Zero address first");
        require(second != address(0), "Zero address second");
        require(prizeBalance > 0, "Empty vault");

        uint256 total = prizeBalance;
        uint256 firstPayout  = (total * 70) / 100;
        uint256 secondPayout = total - firstPayout;
        prizeBalance = 0;
        gameEnded = true;

        (bool sentFirst, ) = payable(first).call{
            value: firstPayout
        }("");
        require(sentFirst, "First transfer failed");

        (bool sentSecond, ) = payable(second).call{
            value: secondPayout
        }("");
        require(sentSecond, "Second transfer failed");

        emit SplitPaid(first, firstPayout, second, secondPayout);
    }

    // ── ADMIN ─────────────────────────────────
    function setStakingPool(
        address _stakingPool
    ) external onlyOwner {
        require(_stakingPool != address(0), "Zero address");
        stakingPool = _stakingPool;
        emit StakingPoolSet(_stakingPool);
    }

    function setTimerGame(
        address _timerGame
    ) external onlyOwner {
        require(_timerGame != address(0), "Zero address");
        timerGame = _timerGame;
        emit TimerGameSet(_timerGame);
    }

    function pauseVault() external onlyOwner {
        vaultPaused = true;
        emit VaultPaused(true);
    }

    function resumeVault() external onlyOwner {
        vaultPaused = false;
        emit VaultPaused(false);
    }

    // Emergency escape — only if something
    // goes critically wrong during testing
    function emergencyWithdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "Nothing to withdraw");
        prizeBalance = 0;
        (bool sent, ) = payable(owner).call{value: bal}("");
        require(sent, "Withdraw failed");
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ── VIEWS ─────────────────────────────────
    function getPrizeBalance()
        external view returns (uint256) {
        return prizeBalance;
    }

    function getTimeUntilNextGrowth()
        external view returns (uint256) {
        uint256 nextGrowth = lastGrowthTime + growthIntervalSeconds;
        if (block.timestamp >= nextGrowth) return 0;
        return nextGrowth - block.timestamp;
    }

    function isGrowthReady()
        external view returns (bool) {
        return (
            growthActive &&
            block.timestamp >=
            lastGrowthTime + growthIntervalSeconds
        );
    }
}
