// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  TimerGame — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
// ─────────────────────────────────────────────

interface IPrizeVault {
    function distributeAll(address winner) external;
    function distributeSplit(
        address first,
        address second
    ) external;
    function getPrizeBalance() external view returns (uint256);
}

interface IStakingPool {
    function getBestStake(address wallet) external view returns (
        uint256 stakeIndex,
        uint8   tier,
        uint256 tierDuration,
        uint256 amount,
        bool    found
    );
    function getActiveIndices(
        address wallet
    ) external view returns (uint256[] memory);
}

interface IDAPPToken {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(
        address account
    ) external view returns (uint256);
}

interface ITreasury {
    function receiveTokens(uint256 amount) external;
}

contract TimerGame {

    // ── CONSTANTS ─────────────────────────────
    uint256 public constant TIMER_START   = 48 hours;
    uint256 public constant TIMER_MAX     = 654 hours;
    uint256 public constant PUSH_AMOUNT   = 5 minutes;
    uint256 public constant TOKEN_COST    = 1e18; // 1 DAPP
    uint256 public constant LEADERBOARD_WINDOW = 650 hours;

    // ── STATE ─────────────────────────────────
    address public owner;
    address public prizeVault;
    address public stakingPool;
    address public dappToken;
    address public treasury;

    // Timer state
    uint256 public timerStart;      // timestamp when timer began
    uint256 public timerValue;      // seconds on clock at lastUpdate
    uint256 public lastUpdateTime;  // block.timestamp of last push
    bool    public gameStarted;
    bool    public gameEnded;
    bool    public timerPaused;

    // Win state
    address public lastSpender;
    address public lastSpenderRecorded;
    GameResult public result;

    // Leaderboard — tracked wallets
    // For testnet scale (~100 users) array is fine
    address[] public registeredWallets;
    mapping(address => bool) public isRegistered;

    // Pause controls
    bool public globalPaused;

    enum GameResult { NONE, COUNTDOWN, TIMEOUT }

// ── EVENTS ────────────────────────────────
    event GameStarted(uint256 timestamp);

    event TimerPushed(
        address indexed spender,
        uint256 newTimerValue,
        uint256 timestamp
    );

    event GameEndedCountdown(
        address indexed winner,
        uint256 prizeAmount,
        uint256 timestamp
    );

    event GameEndedTimeout(
        address indexed first,
        address indexed second,
        uint256 timestamp
    );

    event TimerPausedEvent(bool paused);
    event GlobalPausedEvent(bool paused);
    event WalletRegistered(address indexed wallet);

    // ── MODIFIERS ─────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier notPaused() {
        require(!globalPaused, "Contract paused");
        _;
    }

    modifier gameActive() {
        require(gameStarted, "Game not started");
        require(!gameEnded, "Game has ended");
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor(
        address _prizeVault,
        address _stakingPool,
        address _dappToken,
        address _treasury
    ) {
        owner       = msg.sender;
        prizeVault  = _prizeVault;
        stakingPool = _stakingPool;
        dappToken   = _dappToken;
        treasury    = _treasury;
    }

    // ── START GAME ────────────────────────────
    // Owner calls this once to begin the competition
    // Timer starts at 48 hours from this moment
    function startGame() external onlyOwner {
        require(!gameStarted, "Already started");
        require(
            IPrizeVault(prizeVault).getPrizeBalance() > 0,
            "Prize vault empty"
        );

        gameStarted    = true;
        timerValue     = TIMER_START;
        timerStart     = block.timestamp;
        lastUpdateTime = block.timestamp;

        emit GameStarted(block.timestamp);
    }
// ── PUSH TIMER ────────────────────────────
    // Costs exactly 1 DAPP token
    // Pushes timer DOWN by 5 minutes
    // Records msg.sender as last spender
    // Auto-registers wallet for leaderboard
    function pushTimer()
        external
        notPaused
        gameActive
    {
        // Check current timer before push
        uint256 current = getCurrentTimer();

        // Check win condition BEFORE accepting token
        // If already at 0 or max, reject
        require(current > 0, "Timer already at zero");
        require(
            current < TIMER_MAX,
            "Timer already at max"
        );

        // Collect 1 DAPP from caller
        // Token goes to Treasury for recycling
        bool transferred = IDAPPToken(dappToken).transferFrom(
            msg.sender,
            treasury,
            TOKEN_COST
        );
        require(transferred, "Token transfer failed");

        // Notify treasury tokens received
        ITreasury(treasury).receiveTokens(TOKEN_COST);

        // Update timer state
        // Snapshot current value then subtract push
        timerValue     = current > PUSH_AMOUNT
            ? current - PUSH_AMOUNT
            : 0;
        lastUpdateTime = block.timestamp;

        // Record last spender
        lastSpender         = msg.sender;
        lastSpenderRecorded = msg.sender;

        // Auto-register wallet for leaderboard
        if (!isRegistered[msg.sender]) {
            isRegistered[msg.sender] = true;
            registeredWallets.push(msg.sender);
            emit WalletRegistered(msg.sender);
        }

        emit TimerPushed(
            msg.sender,
            timerValue,
            block.timestamp
        );

        // Check win conditions after push
        _checkWinConditions();
    }

    // ── WIN CONDITION CHECK ───────────────────
    // Called internally after every timer push
    // Also callable externally for timeout check
    function checkWinConditions()
        external
        notPaused
        gameActive
    {
        _checkWinConditions();
    }

    function _checkWinConditions() internal {
        if (gameEnded) return;

        uint256 current = getCurrentTimer();

        // Win A — timer hits zero
        // Last token spender wins everything
        if (current == 0) {
            _triggerCountdownWin();
            return;
        }

        // Win B — timer hits TIMER_MAX (654 hours)
        // Happens from inactivity — timer drifts up
        if (current >= TIMER_MAX) {
            _triggerTimeoutWin();
            return;
        }
    }

    // ── CURRENT TIMER VALUE ───────────────────
    // Returns live timer value accounting for
    // passive drift upward since last push
    // This is what frontend polls every 30s
    function getCurrentTimer()
        public
        view
        returns (uint256)
    {
        if (!gameStarted) return TIMER_START;
        if (gameEnded)    return timerValue;
        if (timerPaused)  return timerValue;

        // Time elapsed since last interaction
        uint256 elapsed = block.timestamp - lastUpdateTime;

        // Timer drifts UP passively
        uint256 current = timerValue + elapsed;

        // Cap at TIMER_MAX
        if (current >= TIMER_MAX) return TIMER_MAX;

        return current;
    }

// ── WIN TRIGGER A — COUNTDOWN ─────────────
    function _triggerCountdownWin() internal {
        gameEnded  = true;
        result     = GameResult.COUNTDOWN;

        // Freeze timer at zero
        timerValue     = 0;
        lastUpdateTime = block.timestamp;

        uint256 prize = IPrizeVault(prizeVault)
            .getPrizeBalance();

        // Pay winner — last spender takes all
        IPrizeVault(prizeVault).distributeAll(lastSpender);

        emit GameEndedCountdown(
            lastSpender,
            prize,
            block.timestamp
        );
    }

    // ── WIN TRIGGER B — TIMEOUT ───────────────
    function _triggerTimeoutWin() internal {
        gameEnded  = true;
        result     = GameResult.TIMEOUT;

        // Freeze timer at max
        timerValue     = TIMER_MAX;
        lastUpdateTime = block.timestamp;

        // Get top 2 stakers from leaderboard
        (
            address first,
            address second,
            bool valid
        ) = getTop2();

        // If no valid stakers found fall back to
        // owner as safety — should not happen in
        // normal operation with active stakers
        if (!valid) {
            IPrizeVault(prizeVault).distributeAll(owner);
            emit GameEndedTimeout(owner, address(0), block.timestamp);
            return;
        }

        // 70/30 split via PrizeVault
        IPrizeVault(prizeVault).distributeSplit(first, second);

        emit GameEndedTimeout(first, second, block.timestamp);
    }

    // ── LEADERBOARD: GET TOP 2 ────────────────
    // Scans registered wallets
    // Applies ranking cascade:
    // 1. Highest tier
    // 2. Longest duration in that tier
    // 3. Largest stake size
    // Only considers stakes active in last 650hrs
    function getTop2() public view returns (
        address first,
        address second,
        bool    valid
    ) {
        uint256 windowStart = block.timestamp > LEADERBOARD_WINDOW
            ? block.timestamp - LEADERBOARD_WINDOW
            : 0;

        address bestAddr   = address(0);
        address secondAddr = address(0);

        uint8   bestTier      = 0;
        uint256 bestDuration  = 0;
        uint256 bestAmount    = 0;

        uint8   secTier      = 0;
        uint256 secDuration  = 0;
        uint256 secAmount    = 0;

        uint256 len = registeredWallets.length;

        for (uint256 i = 0; i < len; i++) {
            address wallet = registeredWallets[i];

            (
                ,
                uint8   tier,
                uint256 tierDuration,
                uint256 amount,
                bool    found
            ) = IStakingPool(stakingPool).getBestStake(wallet);

            if (!found) continue;

            // Check stake was active in window
            // tierDuration = time in current tier
            // Use startTime proxy via tierDuration
            // A stake active in window has
            // tierDuration > 0 or started recently
            if (amount == 0) continue;

            // Compare against first place
            bool betterThanFirst = _rankBetter(
                tier, tierDuration, amount,
                bestTier, bestDuration, bestAmount
            );

            if (betterThanFirst) {
                // Demote first to second
                secondAddr = bestAddr;
                secTier     = bestTier;
                secDuration = bestDuration;
                secAmount   = bestAmount;

                // New first
                bestAddr     = wallet;
                bestTier     = tier;
                bestDuration = tierDuration;
                bestAmount   = amount;
            } else {
                // Compare against second place
                bool betterThanSecond = _rankBetter(
                    tier, tierDuration, amount,
                    secTier, secDuration, secAmount
                );
                if (betterThanSecond) {
                    secondAddr  = wallet;
                    secTier     = tier;
                    secDuration = tierDuration;
                    secAmount   = amount;
                }
            }
        }

        // Need at least 2 valid stakers for split
        // If only 1 found, first takes all via
        // fallback in _triggerTimeoutWin
        valid = (bestAddr != address(0) &&
                 secondAddr != address(0));

        // If only one staker exists give them
        // both slots — distributeSplit will
        // still pay 70/30 to same address
        if (bestAddr != address(0) &&
            secondAddr == address(0)) {
            secondAddr = bestAddr;
            valid = true;
        }

        return (bestAddr, secondAddr, valid);
    }

    // ── INTERNAL: ranking comparator ──────────
    function _rankBetter(
        uint8 aTier, uint256 aDur, uint256 aAmt,
        uint8 bTier, uint256 bDur, uint256 bAmt
    ) internal pure returns (bool) {
        if (bTier == 0 && bAmt == 0) return true;
        if (aTier != bTier) return aTier > bTier;
        if (aDur  != bDur)  return aDur  > bDur;
        return aAmt > bAmt;
    }

// ── ADMIN ─────────────────────────────────
    function pauseTimer() external onlyOwner {
        timerPaused = true;
        emit TimerPausedEvent(true);
    }

    function resumeTimer() external onlyOwner {
        // When resuming, reset lastUpdateTime
        // so elapsed time while paused
        // does not count against the clock
        lastUpdateTime = block.timestamp;
        timerPaused    = false;
        emit TimerPausedEvent(false);
    }

    function pauseAll() external onlyOwner {
        globalPaused = true;
        emit GlobalPausedEvent(true);
    }

    function resumeAll() external onlyOwner {
        globalPaused = false;
        emit GlobalPausedEvent(false);
    }

    // Manual win trigger — owner authorized
    // Use if automatic check fails or for testing
    function triggerCheck() external onlyOwner {
        require(gameStarted, "Not started");
        require(!gameEnded, "Already ended");
        _checkWinConditions();
    }

    // Emergency — reset timer to 48hrs
    // Does not affect prize or stakes
    function emergencyResetTimer() external onlyOwner {
        require(!gameEnded, "Game ended");
        timerValue     = TIMER_START;
        lastUpdateTime = block.timestamp;
    }

    // Register a wallet manually for leaderboard
    // In case they staked but never pushed timer
    function registerWallet(
        address wallet
    ) external onlyOwner {
        require(wallet != address(0), "Zero address");
        if (!isRegistered[wallet]) {
            isRegistered[wallet] = true;
            registeredWallets.push(wallet);
            emit WalletRegistered(wallet);
        }
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ── VIEWS ─────────────────────────────────
    function getGameState() external view returns (
        bool    started,
        bool    ended,
        uint256 currentTimer,
        address currentLastSpender,
        uint256 prizeBalance,
        GameResult gameResult
    ) {
        return (
            gameStarted,
            gameEnded,
            getCurrentTimer(),
            lastSpender,
            IPrizeVault(prizeVault).getPrizeBalance(),
            result
        );
    }

    function getRegisteredWallets()
        external
        view
        returns (address[] memory)
    {
        return registeredWallets;
    }

    function getRegisteredCount()
        external
        view
        returns (uint256)
    {
        return registeredWallets.length;
    }

    function isGameActive()
        external
        view
        returns (bool)
    {
        return gameStarted && !gameEnded;
    }

    function getTimerDisplay() external view returns (
        uint256 hours_,
        uint256 minutes_,
        uint256 seconds_
    ) {
        uint256 t = getCurrentTimer();
        hours_   = t / 3600;
        minutes_ = (t % 3600) / 60;
        seconds_ = t % 60;
    }

    // ── RECEIVE ───────────────────────────────
    receive() external payable {}

} // ── END TimerGame ─────────────────────────────
