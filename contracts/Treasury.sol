// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  Treasury — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
//  Version  : 2 — Fixed emission window
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

    // ── SACRED CONSTANTS ──────────────────────
    // 1 ETH in prize vault = 1000 DAPP budget
    uint256 public constant TOKENS_PER_ETH = 1000;

    // Fixed emission window = 654 hours always
    // 654 * 60 * 60 = 2,354,400 seconds
    uint256 public constant EMISSION_WINDOW = 2354400;

    // Emission floor — never distribute below this
    uint256 public constant EMISSION_FLOOR = 1e16; // 0.01 DAPP

    // Tracks total ever distributed
    uint256 public totalEmitted;

    // ── EVENTS ────────────────────────────────
    event Distributed(
        address indexed recipient,
        uint256 amount
    );

    event EmissionsPaused(bool paused);

    event StakingPoolSet(
        address indexed stakingPool
    );

    event ReceivedTokens(
        address indexed sender,
        uint256 amount
    );

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
        require(
            !emissionsPaused,
            "Emissions paused"
        );
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor(address _dappToken) {
        owner     = msg.sender;
        dappToken = _dappToken;
    }

    // ── CORE: DISTRIBUTE ──────────────────────
    // Called by StakingPool to pay a staker
    function distribute(
        address recipient,
        uint256 amount
    ) external onlyStakingPool emissionsActive {
        require(
            recipient != address(0),
            "Zero address"
        );

        // Enforce emission floor
        uint256 payout = amount < EMISSION_FLOOR
            ? EMISSION_FLOOR
            : amount;

        // Mint more if treasury balance is low
        uint256 bal = IDAPPToken(dappToken)
            .balanceOf(address(this));

        if (bal < payout) {
            IDAPPToken(dappToken).mint(
                address(this),
                payout - bal
            );
        }

        IDAPPToken(dappToken).transfer(recipient, payout);
        totalEmitted += payout;

        emit Distributed(recipient, payout);
    }

    // ── SACRED RULE: EMISSION MATH ────────────
    // 1 ETH in prize vault = 1000 DAPP budget
    // Distributed evenly over 654 hours
    //
    // tokensPerSecond =
    //   (prizePoolWei * TOKENS_PER_ETH * 1e18)
    //   / 1e18
    //   / EMISSION_WINDOW
    //
    // Simplified:
    //   tokensPerSecond =
    //     (prizePoolWei * TOKENS_PER_ETH)
    //     / EMISSION_WINDOW
    //
    // Example:
    //   1 ETH pool = 1e18 wei
    //   budget     = 1e18 * 1000 = 1e21
    //   per second = 1e21 / 2354400
    //              ≈ 424,957 wei of DAPP/sec
    //   over 654hrs = ~1000 DAPP total ✅
    function calculateEmissionRate(
        uint256 prizePoolWei
    ) public pure returns (uint256 tokensPerSecond) {

        if (prizePoolWei == 0) {
            return EMISSION_FLOOR;
        }

        // Full token budget for this pool size
        // prizePoolWei * 1000 gives budget in
        // token-wei (since 1 ETH = 1e18 wei and
        // 1 DAPP = 1e18 token-wei, the ratio holds)
        uint256 budget = prizePoolWei * TOKENS_PER_ETH;

        // Divide by window to get per-second rate
        tokensPerSecond = budget / EMISSION_WINDOW;

        // Never below floor
        if (tokensPerSecond < EMISSION_FLOOR) {
            tokensPerSecond = EMISSION_FLOOR;
        }

        return tokensPerSecond;
    }

    // ── RECYCLING ─────────────────────────────
    // Accepts tokens returned from TimerGame
    // when users spend DAPP to push the timer
    function receiveTokens(
        uint256 amount
    ) external {
        require(amount > 0, "Zero amount");
        emit ReceivedTokens(msg.sender, amount);
    }

    // ── VIEWS ─────────────────────────────────
    function getTreasuryBalance()
        public
        view
        returns (uint256)
    {
        return IDAPPToken(dappToken)
            .balanceOf(address(this));
    }

    // Helper — what would emission rate be
    // at a given prize pool size
    // Useful for frontend display
    function previewEmissionRate(
        uint256 prizePoolWei
    ) external pure returns (
        uint256 tokensPerSecond,
        uint256 tokensPerHour,
        uint256 totalBudget
    ) {
        tokensPerSecond = calculateEmissionRate(
            prizePoolWei
        );
        tokensPerHour   = tokensPerSecond * 3600;
        totalBudget     = prizePoolWei * TOKENS_PER_ETH;

        return (tokensPerSecond, tokensPerHour, totalBudget);
    }

    // ── ADMIN ─────────────────────────────────
    function setStakingPool(
        address _stakingPool
    ) public onlyOwner {
        require(
            _stakingPool != address(0),
            "Zero address"
        );
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
}
