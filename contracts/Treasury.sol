// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  Treasury — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
// ─────────────────────────────────────────────

interface IDAPPToken {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(
        address account
    ) external view returns (uint256);

    function mint(
        address recipient,
        uint256 amount
    ) external;
}

contract Treasury {

    // ── STATE ─────────────────────────────────
    address public owner;
    address public dappToken;
    address public stakingPool;

    bool public emissionsPaused;

    // Emission floor — never distribute below this
    // per eligible staker per calculation
    uint256 public constant EMISSION_FLOOR = 1e16; // 0.01 DAPP

    // Sacred rule constant
    // 1 ETH in prize = 1000 DAPP emitted
    uint256 public constant TOKENS_PER_ETH = 1000;

    // Tracks total ever distributed
    uint256 public totalEmitted;

    // ── EVENTS ────────────────────────────────
    event Distributed(
        address indexed recipient,
        uint256 amount
    );

    event EmissionsPaused(bool paused);

    event StakingPoolSet(address indexed stakingPool);

    event ReceivedTokens(uint256 amount);

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

    modifier emissionsActive() {
        require(!emissionsPaused, "Emissions paused");
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor(address _dappToken) {
        owner     = msg.sender;
        dappToken = _dappToken;
    }

    // ── CORE EMISSION LOGIC ───────────────────

    // Called by StakingPool to pay a staker their share
    function distribute(
        address recipient,
        uint256 amount
    ) external onlyStakingPool emissionsActive {
        require(recipient != address(0), "Zero address");

        // Enforce emission floor
        uint256 payout = amount < EMISSION_FLOOR
            ? EMISSION_FLOOR
            : amount;

        // Check treasury balance
        uint256 treasuryBalance = IDAPPToken(dappToken)
            .balanceOf(address(this));

        // Mint more if treasury runs low
        if (treasuryBalance < payout) {
            IDAPPToken(dappToken).mint(address(this), payout);
        }

        IDAPPToken(dappToken).transfer(recipient, payout);
        totalEmitted += payout;

        emit Distributed(recipient, payout);
    }

    // ── EMISSION MATH (pure — no state change) ─

    // Sacred rule: 1 ETH = 1000 DAPP
    // over the current variable time window
    // timerSeconds = current timer value in seconds
    // maxTimerSeconds = 654 hours in seconds
    // prizePoolWei = current ETH in prize vault
    function calculateEmissionRate(
        uint256 prizePoolWei,
        uint256 timerSeconds,
        uint256 maxTimerSeconds
    ) public pure returns (uint256 tokensPerSecond) {

        // Total tokens this prize pool size unlocks
        // prizePoolWei / 1e18 * TOKENS_PER_ETH * 1e18
        uint256 totalTokensForPool =
            (prizePoolWei * TOKENS_PER_ETH);

        // Timer proximity ratio
        // Closer to 0:00 = smaller ratio = slower rate
        // Closer to 654hrs = larger ratio = faster rate
        // ratio = timerSeconds / maxTimerSeconds
        // tokensPerSecond = totalTokensForPool
        //                   * timerSeconds
        //                   / maxTimerSeconds
        //                   / maxTimerSeconds
        // Dividing by maxTimerSeconds twice:
        // once to normalize ratio,
        // once to convert total→per-second
        if (timerSeconds == 0) {
            return EMISSION_FLOOR;
        }

        tokensPerSecond =
            (totalTokensForPool * timerSeconds)
            / maxTimerSeconds
            / maxTimerSeconds;

        // Never below floor
        if (tokensPerSecond < EMISSION_FLOOR) {
            tokensPerSecond = EMISSION_FLOOR;
        }

        return tokensPerSecond;
    }

    // ── RECYCLING ─────────────────────────────
    // Accepts tokens returned from timer interactions
    function receiveTokens(uint256 amount) external {
        require(amount > 0, "Zero amount");
        emit ReceivedTokens(amount);
        // Tokens transferred in by StakingPool/TimerGame
        // via transferFrom — this just logs the event
    }

    // ── ADMIN ─────────────────────────────────
    function setStakingPool(
        address _stakingPool
    ) public onlyOwner {
        require(_stakingPool != address(0), "Zero address");
        stakingPool = _stakingPool;
        emit StakingPoolSet(_stakingPool);
    }

    function pauseEmissions() public onlyOwner {
        emissionsPaused = true;
        emit EmissionsPaused(true);
    }

    function resumeEmissions() public onlyOwner {
        emissionsPaused = false;
        emit EmissionsPaused(false);
    }

    function transferOwnership(
        address newOwner
    ) public onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ── VIEWS ─────────────────────────────────
    function getTreasuryBalance()
        public view returns (uint256) {
        return IDAPPToken(dappToken).balanceOf(address(this));
    }
}
