 // ── CONTRACTS ─────────────────────────────
const ADDRESSES = {
  dappToken:   "0x3d0cB8929c22F93A9dd33921E6f43C1621FCfC04",
  treasury:    "0x9935aea651d21Af9C69fE6C650cD7C272e49e270",
  prizeVault:  "0x59B2971AD75B8cc361656515B04aBed591Fe99Ae",
  stakingPool: "0xA813a05a01AeA07A6a0c0ca0a5D6491343255D4C",
  timerGame:   "0x95C491280c172A963C7DeB559d8b4CAF95986744",
  faucet:      "0xe39900fCcA537148B2AC053c867E5ae4716Cc0BA",
};

const CHAIN_ID = "0x66eee"; // Arbitrum Sepolia

// ── ABIS ──────────────────────────────────
const ABI_TOKEN = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function transfer(address,uint256) returns (bool)",
];

const ABI_VAULT = [
  "function getPrizeBalance() view returns (uint256)",
  "function growthActive() view returns (bool)",
  "function getTimeUntilNextGrowth() view returns (uint256)",
  "function isGrowthReady() view returns (bool)",
];

const ABI_STAKING = [
  "function stake() payable",
  "function unstake(uint256)",
  "function claimRewards(uint256)",
  "function upgradeTier(uint256)",
  "function getStakeCount(address) view returns (uint256)",
  "function getStake(address,uint256) view returns (tuple(uint256 index,uint256 amount,uint256 startTime,uint256 tierStartTime,uint256 pendingRewards,uint256 lastClaimTime,uint8 tier,bool active))",
  "function getActiveIndices(address) view returns (uint256[])",
  "function getBestStake(address) view returns (uint256,uint8,uint256,uint256,bool)",
  "function getEmissionShare(address,uint256) view returns (uint256)",
  "function totalPooledETH() view returns (uint256)",
  "function activeStakeCount() view returns (uint256)",
  "function lastEmissionTime() view returns (uint256)",
];

const ABI_TIMER = [
  "function getCurrentTimer() view returns (uint256)",
  "function getTimerDisplay() view returns (uint256,uint256,uint256)",
  "function getGameState() view returns (bool,bool,uint256,address,uint256,uint8)",
  "function pushTimer()",
  "function pushAmount() view returns (uint256)",
  "function PUSH_AMOUNT() view returns (uint256)",
  "function isGameActive() view returns (bool)",
  "function lastSpender() view returns (address)",
  "function registeredWallets(uint256) view returns (address)",
  "function getRegisteredCount() view returns (uint256)",
  "function getBestStake(address) view returns (uint256,uint8,uint256,uint256,bool)",
];

const ABI_FAUCET = [
  "function claim()",
  "function timeUntilNextClaim(address) view returns (uint256)",
  "function claimAmount() view returns (uint256)",
  "function getBalance() view returns (uint256)",
  "function canClaim(address) view returns (bool)",
];

const ABI_TREASURY = [
  "function calculateEmissionRate(uint256 prizePoolWei) view returns (uint256 tokensPerSecond)",
  "function previewEmissionRate(uint256 prizePoolWei) view returns (uint256 tokensPerSecond, uint256 tokensPerHour, uint256 totalBudget)",
  "function getTreasuryBalance() view returns (uint256)",
];

// Formats a push amount in seconds for display,
// e.g. 144000 → "40 hours" / "40h"
function formatPushAmount(secs, short = false) {
  if (secs >= 3600 && secs % 3600 === 0) {
    const h = secs / 3600;
    return short ? `${h}h` : `${h} hour${h === 1 ? "" : "s"}`;
  }
  const m = Math.round(secs / 60);
  return short ? `${m}min` : `${m} minute${m === 1 ? "" : "s"}`;
}

// Wraps any promise with a timeout so stale
// providers fail fast instead of hanging forever
function withTimeout(promise, ms = 8000) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error("RPC timeout")), ms)
    ),
  ]);
}
// ── HOOKS ──────────────────────────────────
const { useState, useEffect, useRef, useCallback } = React;

// Wallet connection hook
function useWallet() {
  const [provider, setProvider]     = useState(null);
  const [signer, setSigner]         = useState(null);
  const [address, setAddress]       = useState(null);
  const [ethBalance, setEthBalance] = useState("0.0000");
  const [connecting, setConnecting] = useState(false);
  const [status, setStatus]         = useState(null);
  // status = { msg, type } type = success|error|pending

  const showStatus = (msg, type = "pending") =>
    setStatus({ msg, type });

  const clearStatus = () => setStatus(null);

  async function connect() {
    if (typeof window.ethereum === "undefined") {
      showStatus("No wallet found. Open in MetaMask or Brave.", "error");
      return;
    }
    try {
      setConnecting(true);
      showStatus("Connecting wallet...", "pending");

      const accounts = await window.ethereum.request({
        method: "eth_requestAccounts",
      });

      if (!accounts || accounts.length === 0) {
        showStatus("No accounts found. Unlock your wallet.", "error");
        setConnecting(false);
        return;
      }

      // Switch to Arbitrum Sepolia
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: CHAIN_ID }],
        });
        DebugHub.logSecurity("Chain Check", "pass");
      } catch (switchErr) {
        if (switchErr.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: CHAIN_ID,
              chainName: "Arbitrum Sepolia",
              nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
              rpcUrls: ["https://sepolia-rollup.arbitrum.io/rpc"],
              blockExplorerUrls: ["https://sepolia.arbiscan.io"],
            }],
          });
          DebugHub.logSecurity("Chain Check", "pass");
        } else {
          DebugHub.logSecurity("Chain Check", "fail");
          DebugHub.logError("switchChain", switchErr);
          showStatus("Failed to switch network.", "error");
          setConnecting(false);
          return;
        }
      }

      // Always resolve signer dynamically — never hardcode address
      const _provider = new ethers.providers.Web3Provider(window.ethereum);
      const _signer   = _provider.getSigner();
      const _address  = await _signer.getAddress();
      const _bal      = await _provider.getBalance(_address);

      setProvider(_provider);
      setSigner(_signer);
      setAddress(_address);
      setEthBalance(
        parseFloat(ethers.utils.formatEther(_bal)).toFixed(4)
      );

      DebugHub.startSession();
      DebugHub.logCheckpoint("Wallet Connected", "pass");

      showStatus("Wallet connected.", "success");
      setTimeout(clearStatus, 3000);
    } catch (err) {
      DebugHub.logError("connect", err);
      showStatus(err.message || "Connection failed.", "error");
    } finally {
      setConnecting(false);
    }
  }

  function disconnect() {
    DebugHub.endSession();
    setProvider(null);
    setSigner(null);
    setAddress(null);
    setEthBalance("0.0000");
    clearStatus();
  }

  // Re-init provider when app comes back to foreground
// Mobile wallets often drop the connection when
// the browser is backgrounded for a few minutes
useEffect(() => {
  if (!window.ethereum) return;

  const handleVisibility = async () => {
    if (document.visibilityState === "visible" && address) {
      try {
        const _provider = new ethers.providers.Web3Provider(window.ethereum);
        const _signer   = _provider.getSigner();
        const _bal      = await _provider.getBalance(address);
        setProvider(_provider);
        setSigner(_signer);
        setEthBalance(
          parseFloat(ethers.utils.formatEther(_bal)).toFixed(4)
        );
      } catch (e) {
        console.warn("Provider refresh failed:", e.message);
      }
    }
  };

  document.addEventListener("visibilitychange", handleVisibility);
  return () =>
    document.removeEventListener("visibilitychange", handleVisibility);
}, [address]);

  return {
    provider, signer, address, ethBalance,
    connecting, status, showStatus, clearStatus,
    connect, disconnect,
  };
}

// Live timer hook — interpolates locally, syncs chain every 30s
function useTimer(provider) {
  const [timerSeconds, setTimerSeconds] = useState(172800); // 48hrs default
  const [gameActive, setGameActive]     = useState(false);
  const chainRef = useRef(172800);

  // Sync from chain
  const syncChain = useCallback(async () => {
    if (!provider) return;
    try {
      const contract = new ethers.Contract(
        ADDRESSES.timerGame, ABI_TIMER, provider
      );
      const active = await contract.isGameActive();
      setGameActive(active);
      if (active) {
        const val = await contract.getCurrentTimer();
        const secs = val.toNumber();
        chainRef.current = secs;
        setTimerSeconds(secs);
      }
    } catch (e) {
      console.warn("Timer sync failed:", e.message);
    }
  }, [provider]);

  // Chain sync every 30s
  useEffect(() => {
    syncChain();
    const interval = setInterval(syncChain, 30000);
    return () => clearInterval(interval);
  }, [syncChain]);

  // Local tick every 1s — timer counts UP passively
  useEffect(() => {
    if (!gameActive) return;
    const tick = setInterval(() => {
      setTimerSeconds(prev => {
        const next = prev + 1;
        // Cap at max
        if (next >= 2354400) return 2354400;
        return next;
      });
    }, 1000);
    return () => clearInterval(tick);
  }, [gameActive]);

  // Format seconds → HH:MM:SS
  function formatTimer(secs) {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    return [h, m, s]
      .map(v => String(v).padStart(2, "0"))
      .join(":");
  }

  // Pressure level for visual styling
  function pressureLevel(secs) {
    if (secs <= 3600) return "pressure";       // under 1hr — red
    if (secs >= 2300000) return "safe";        // near 654hrs — green
    return "";
  }

  return {
    timerSeconds,
    timerDisplay: formatTimer(timerSeconds),
    pressureClass: pressureLevel(timerSeconds),
    gameActive,
    syncChain,
  };
}

// ── ARENA TAB ─────────────────────────────
function ArenaTab({ wallet, timer }) {
  const { signer, address, provider, showStatus } = wallet;
  const { timerDisplay, pressureClass, gameActive } = timer;

  const [prizeEth, setPrizeEth]       = useState("0.0000");
  const [dappBalance, setDappBalance] = useState("0.00");
  const [lastSpender, setLastSpender] = useState(null);
  const [pooledEth, setPooledEth]     = useState("0.0000");
  const [stakeCount, setStakeCount]   = useState("0");
  const [pushing, setPushing]         = useState(false);
  const [pushSecs, setPushSecs]       = useState(40 * 3600);
  const [allowance, setAllowance]     = useState(
    ethers.BigNumber.from(0)
  );

  async function loadArena() {
    if (!provider) return;
    try {
      const vault    = new ethers.Contract(ADDRESSES.prizeVault, ABI_VAULT, provider);
      const staking  = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, provider);
      const timerC   = new ethers.Contract(ADDRESSES.timerGame, ABI_TIMER, provider);

      const [prize, pooled, count, spender, pushAmt] = await withTimeout(
  Promise.all([
        vault.getPrizeBalance(),
        staking.totalPooledETH(),
        staking.activeStakeCount(),
        timerC.lastSpender(),
        // Getter name varies across deployments
        // (pushAmount vs PUSH_AMOUNT); oldest have
        // neither — fall back to 40h, don't fail load
        timerC.pushAmount()
          .catch(() => timerC.PUSH_AMOUNT())
          .catch(() => ethers.BigNumber.from(40 * 3600)),
      ])
     );
    
     
      setPrizeEth(
        parseFloat(ethers.utils.formatEther(prize)).toFixed(4)
      );
      setPooledEth(
        parseFloat(ethers.utils.formatEther(pooled)).toFixed(4)
      );
      setStakeCount(count.toString());
      setLastSpender(spender);
      setPushSecs(pushAmt.toNumber());

      // Per-wallet reads — only if connected
      if (address) {
        const token = new ethers.Contract(ADDRESSES.dappToken, ABI_TOKEN, provider);
        const [bal, allow] = await Promise.all([
          token.balanceOf(address),
          token.allowance(address, ADDRESSES.timerGame),
        ]);
        setDappBalance(
          parseFloat(ethers.utils.formatEther(bal)).toFixed(2)
        );
        setAllowance(allow);
      }
    } catch (e) {
      console.warn("Arena load error:", e.message);
    }
  }

  useEffect(() => { loadArena(); }, [address, provider]);

  async function handleApprove() {
    if (!signer) return;
    try {
      showStatus("Approving DAPP for timer...", "pending");
      const token = new ethers.Contract(ADDRESSES.dappToken, ABI_TOKEN, signer);
      const max   = ethers.constants.MaxUint256;
      const nonce = await signer.provider.getTransactionCount(address, "pending");
      DebugHub.logCheckpoint("Approve Requested", "pass");
      const tx    = await token.approve(ADDRESSES.timerGame, max, { nonce: nonce });
      DebugHub.logCheckpoint("Approve Submitted", "pass");
      showStatus("Approval pending...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Approve Confirmed", "pass");
      showStatus("DAPP approved. Ready to push.", "success");
      await loadArena();
    } catch (e) {
      DebugHub.logError("approve", e);
      DebugHub.logCheckpoint("Approve Confirmed", "fail");
      showStatus(e.message || "Approval failed.", "error");
    }
  }

  async function handlePush() {
    if (!signer) return;
    try {
      setPushing(true);
      showStatus("Pushing timer — confirm in wallet...", "pending");
      const game     = new ethers.Contract(ADDRESSES.timerGame, ABI_TIMER, signer);
      const feeData  = await signer.provider.getFeeData();
      const nonce    = await signer.provider.getTransactionCount(address, "pending");
      const __gasStart = Date.now();
      const gasEst   = await game.estimateGas.pushTimer();
      DebugHub.logPerf("gasEstimate_pushTimer", Date.now() - __gasStart);
      const gasLimit = gasEst.mul(150).div(100);
      DebugHub.logCheckpoint("Push Timer Requested", "pass");
      const tx = await game.pushTimer({
        nonce,
        gasLimit,
        maxFeePerGas:         feeData.maxFeePerGas.mul(130).div(100),
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas.mul(130).div(100),
      });
      DebugHub.logCheckpoint("Push Timer Submitted", "pass");
      showStatus("Transaction sent...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Push Timer Confirmed", "pass");
      showStatus(`Timer pushed -${formatPushAmount(pushSecs)}!`, "success");
      timer.syncChain();
      await loadArena();
    } catch (e) {
      DebugHub.logError("pushTimer", e);
      DebugHub.logCheckpoint("Push Timer Confirmed", "fail");
      showStatus(e.reason || e.message || "Push failed.", "error");
    } finally {
      setPushing(false);
    }
  }

  const needsApproval = allowance.lt(ethers.utils.parseEther("1"));
  const hasEnoughDapp = parseFloat(dappBalance) >= 1;

  // Shorten stake ID for last spender display
  function shortId(addr) {
    if (!addr || addr === ethers.constants.AddressZero) return "—";
    return addr.slice(2, 8).toUpperCase();
  }

  return React.createElement("div", { className: "tab-content" },

    // Timer hero
    React.createElement("div", { className: "timer-hero" },
      React.createElement("div", { className: "timer-label" },
        gameActive ? "LIVE COUNTDOWN" : "AWAITING START"
      ),
      React.createElement("div", {
        className: `timer-display ${pressureClass}`
      }, timerDisplay),
      React.createElement("div", { className: "timer-sublabel" },
        "HH : MM : SS"
      )
    ),

    // Prize pool
    React.createElement("div", { className: "prize-card" },
      React.createElement("div", { className: "prize-label" }, "Prize Pool"),
      React.createElement("div", { className: "prize-amount" },
        prizeEth, " ETH"
      ),
    ),

    // Stats row
    React.createElement("div", { className: "stats-row" },
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "Staked ETH"),
        React.createElement("div", { className: "stat-value blue" },
          pooledEth
        )
      ),
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "Active Stakes"),
        React.createElement("div", { className: "stat-value green" },
          stakeCount
        )
      )
    ),

    // Last spender
    React.createElement("div", { className: "stats-row" },
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "Last Push"),
        React.createElement("div", { className: "stat-value orange" },
          shortId(lastSpender)
        )
      ),
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "Your DAPP"),
        React.createElement("div", { className: "stat-value orange" },
          address ? dappBalance : "—"
        )
      )
    ),

    // Push timer card
    address && React.createElement("div", { className: "push-card" },
      React.createElement("div", { className: "push-card-header" },
        React.createElement("div", { className: "push-card-title" },
          "Push The Timer"
        ),
        React.createElement("div", { className: "dapp-balance-pill" },
          dappBalance, " DAPP"
        )
      ),
      React.createElement("div", { className: "push-info" },
        React.createElement("span", { className: "push-info-text" },
          `Spend 1 DAPP → timer drops ${formatPushAmount(pushSecs)}`
        ),
        React.createElement("span", { className: "push-info-cost" },
          "1 DAPP"
        )
      ),
      needsApproval
        ? React.createElement("button", {
            className: "btn-push",
            onClick: handleApprove,
          }, "Approve DAPP First")
        : React.createElement("button", {
            className: "btn-push",
            onClick: handlePush,
            disabled: pushing || !hasEnoughDapp || !gameActive,
          },
            pushing
              ? React.createElement(React.Fragment, null,
                  React.createElement("span", { className: "spinner" }),
                  "Pushing..."
                )
              : !gameActive ? "Game Not Started"
              : !hasEnoughDapp ? "Not Enough DAPP"
              : `Push Timer −${formatPushAmount(pushSecs, true)}`
          )
    ),

    !address && React.createElement("div", { className: "empty-state" },
      "Connect your wallet to push the timer and view your balances."
    )
  );
}

// ── MY STAKES TAB ─────────────────────────
function MyStakesTab({ wallet }) {
  const { signer, address, provider, showStatus } = wallet;

  const [stakes, setStakes]         = useState([]);
  const [ethInput, setEthInput]     = useState("");
  const [staking, setStaking]       = useState(false);
  const [loading, setLoading]       = useState(false);
  const [dappBal, setDappBal]       = useState("0.00");
  const [emissionRate, setEmission] = useState("0");

  async function loadStakes() {
    if (!address || !provider) return;
    setLoading(true);
    try {
      const pool  = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, provider);
      const token = new ethers.Contract(ADDRESSES.dappToken, ABI_TOKEN, provider);
      const vault = new ethers.Contract(ADDRESSES.prizeVault, ABI_VAULT, provider);
      const treas = new ethers.Contract(ADDRESSES.treasury, ABI_TREASURY, provider);

      const [indices, bal, prize] = await withTimeout(
  Promise.all([
        pool.getActiveIndices(address),
        token.balanceOf(address),
        vault.getPrizeBalance(),
      ])
     );
     
      setDappBal(
        parseFloat(ethers.utils.formatEther(bal)).toFixed(2)
      );

      // Calculate emission rate directly — no contract call
// Sacred rule: 1 ETH = 1000 DAPP over 654 hours
// prize is already a BigNumber in wei
const EMISSION_WINDOW = 2354400; // 654 hours in seconds
const TOKENS_PER_ETH = 1000;

// Total budget in token-wei
const budgetWei = prize.mul(TOKENS_PER_ETH);

// Per second rate
const ratePerSec = budgetWei.div(EMISSION_WINDOW);

// Per hour
const ratePerHour = ratePerSec.mul(3600);

setEmission(
  parseFloat(ethers.utils.formatEther(ratePerHour)).toFixed(6)
);

      // Load each active stake
      const loaded = [];

const totalRatePerSec =
  prize.mul(1000).div(2354400);

const totalPooled =
  await pool.totalPooledETH();

const lastEmission =
  (await pool.lastEmissionTime()).toNumber();

const nowSec = Math.floor(Date.now() / 1000);
const gapSeconds = Math.max(0, nowSec - lastEmission);

for (let i = 0; i < indices.length; i++) {

  const idx = indices[i].toNumber();
  const s = await pool.getStake(address, idx);

  const tier = Number(s.tier);

  const tierMult =
    tier === 3 ? 135 :
    tier === 2 ? 125 :
    100;

  const weighted =
    s.amount.mul(tierMult).div(100);

  let stakeRatePerSec =
    ethers.BigNumber.from(0);

  if (!totalPooled.isZero()) {
    stakeRatePerSec =
      totalRatePerSec
        .mul(weighted)
        .div(totalPooled);
  }

  const onChainPending = parseFloat(
    ethers.utils.formatEther(s.pendingRewards)
  );
  const stakeRate = Number(
    ethers.utils.formatEther(stakeRatePerSec)
  );

  // Add virtual accrual for time since
  // last on-chain emission snapshot
  const virtualPending =
    onChainPending + (stakeRate * gapSeconds);

  loaded.push({
    index: idx,
    amount: ethers.utils.formatEther(s.amount),
    startTime: s.startTime.toNumber(),
    tierStart: s.tierStartTime.toNumber(),
    pending: virtualPending.toString(),
    ratePerSec: stakeRate,
    tier,
    active: s.active,
  });
}

setStakes(loaded);

    } catch (e) {
      console.warn("Stakes load error:", e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { loadStakes(); }, [address, provider]);

 // Local interpolation tick — updates displayed
// pending rewards every second between chain syncs
useEffect(() => {
  if (stakes.length === 0) return;
  const tick = setInterval(() => {
    setStakes(prev => prev.map(s => ({
      ...s,
      pending: (parseFloat(s.pending) + s.ratePerSec).toString(),
    })));
  }, 1000);
  return () => clearInterval(tick);
}, [stakes.length]);

  async function handleStake() {
    if (!signer || !ethInput) return;
    try {
      setStaking(true);
      showStatus("Staking ETH — confirm in wallet...", "pending");
      const pool    = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, signer);
      const value   = ethers.utils.parseEther(ethInput);
      const feeData = await signer.provider.getFeeData();
      const nonce   = await signer.provider.getTransactionCount(address, "pending");
      const __gasStart = Date.now();
      const gasEst  = await pool.estimateGas.stake({ value });
      DebugHub.logPerf("gasEstimate_stake", Date.now() - __gasStart);
      DebugHub.logCheckpoint("Stake Requested", "pass");
      const tx = await pool.stake({
        value,
        nonce:                nonce,
        gasLimit:             gasEst.mul(150).div(100),
        maxFeePerGas:         feeData.maxFeePerGas.mul(130).div(100),
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas.mul(130).div(100),
      });
      DebugHub.logCheckpoint("Stake Submitted", "pass");
      showStatus("Transaction sent...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Stake Confirmed", "pass");
      showStatus("Stake created!", "success");
      setEthInput("");
      await loadStakes();
    } catch (e) {
      DebugHub.logError("stake", e);
      DebugHub.logCheckpoint("Stake Confirmed", "fail");
      showStatus(e.reason || e.message || "Stake failed.", "error");
    } finally {
      setStaking(false);
    }
  }

  async function handleUnstake(idx) {
    if (!signer) return;
    try {
      showStatus("Unstaking — confirm in wallet...", "pending");
      const pool    = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, signer);
      const feeData = await signer.provider.getFeeData();
      const nonce   = await signer.provider.getTransactionCount(address, "pending");
      const __gasStart = Date.now();
      const gasEst  = await pool.estimateGas.unstake(idx);
      DebugHub.logPerf("gasEstimate_unstake", Date.now() - __gasStart);
      DebugHub.logCheckpoint("Unstake Requested", "pass");
      const tx = await pool.unstake(idx, {
        nonce:                nonce,
        gasLimit:             gasEst.mul(150).div(100),
        maxFeePerGas:         feeData.maxFeePerGas.mul(130).div(100),
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas.mul(130).div(100),
      });
      DebugHub.logCheckpoint("Unstake Submitted", "pass");
      showStatus("Transaction sent...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Unstake Confirmed", "pass");
      showStatus("Unstaked successfully.", "success");
      await loadStakes();
    } catch (e) {
      DebugHub.logError("unstake", e);
      DebugHub.logCheckpoint("Unstake Confirmed", "fail");
      showStatus(e.reason || e.message || "Unstake failed.", "error");
    }
  }

  async function handleClaim(idx) {
    if (!signer) return;
    try {
      showStatus("Claiming rewards — confirm in wallet...", "pending");
      const pool    = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, signer);
      const feeData = await signer.provider.getFeeData();
      const nonce   = await signer.provider.getTransactionCount(address, "pending");
      const __gasStart = Date.now();
      const gasEst  = await pool.estimateGas.claimRewards(idx);
      DebugHub.logPerf("gasEstimate_claimRewards", Date.now() - __gasStart);
      DebugHub.logCheckpoint("Claim Rewards Requested", "pass");
      const tx = await pool.claimRewards(idx, {
        nonce:                nonce,
        gasLimit:             gasEst.mul(150).div(100),
        maxFeePerGas:         feeData.maxFeePerGas.mul(130).div(100),
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas.mul(130).div(100),
      });
      DebugHub.logCheckpoint("Claim Rewards Submitted", "pass");
      showStatus("Transaction sent...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Claim Rewards Confirmed", "pass");
      showStatus("Rewards claimed!", "success");
      await loadStakes();
    } catch (e) {
      DebugHub.logError("claimRewards", e);
      DebugHub.logCheckpoint("Claim Rewards Confirmed", "fail");
      showStatus(e.reason || e.message || "Claim failed.", "error");
    }
  }

  async function handleUpgrade(idx) {
    if (!signer) return;
    try {
      showStatus("Upgrading tier — confirm in wallet...", "pending");
      const pool    = new ethers.Contract(ADDRESSES.stakingPool, ABI_STAKING, signer);
      const feeData = await signer.provider.getFeeData();
      const nonce   = await signer.provider.getTransactionCount(address, "pending");
      const __gasStart = Date.now();
      const gasEst  = await pool.estimateGas.upgradeTier(idx);
      DebugHub.logPerf("gasEstimate_upgradeTier", Date.now() - __gasStart);
      DebugHub.logCheckpoint("Upgrade Requested", "pass");
      const tx = await pool.upgradeTier(idx, {
        nonce:                nonce,
        gasLimit:             gasEst.mul(150).div(100),
        maxFeePerGas:         feeData.maxFeePerGas.mul(130).div(100),
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas.mul(130).div(100),
      });
      DebugHub.logCheckpoint("Upgrade Submitted", "pass");
      showStatus("Transaction sent...", "pending");
      await tx.wait();
      DebugHub.logCheckpoint("Upgrade Confirmed", "pass");
      showStatus("Tier upgraded!", "success");
      await loadStakes();
    } catch (e) {
      DebugHub.logError("upgradeTier", e);
      DebugHub.logCheckpoint("Upgrade Confirmed", "fail");
      showStatus(e.reason || e.message || "Upgrade failed.", "error");
    }
  }

  function tierLabel(t) {
    if (t === 3) return "T3 ×1.35";
    if (t === 2) return "T2 ×1.25";
    return "T1 Base";
  }

  function tierClass(t) {
    if (t === 3) return "t3";
    if (t === 2) return "t2";
    return "t1";
  }

  function daysActive(startTime) {
    const diff = Math.floor((Date.now() / 1000) - startTime);
    const d    = Math.floor(diff / 86400);
    const h    = Math.floor((diff % 86400) / 3600);
    return `${d}d ${h}h`;
  }

  function canUpgrade(stake) {
    const age = Math.floor(Date.now() / 1000) - stake.startTime;
    if (stake.tier === 1 && age >= 15 * 86400) return true;
    if (stake.tier === 2 && age >= 30 * 86400) return true;
    return false;
  }

  // Generate cosmetic stake ID from index + address
  function stakeId(addr, idx) {
    const raw = addr.slice(2, 6) + idx.toString(16).padStart(2, "0");
    return raw.toUpperCase().slice(0, 6);
  }

  if (!address) {
    return React.createElement("div", { className: "tab-content" },
      React.createElement("div", { className: "empty-state" },
        "Connect your wallet to view and manage your stakes."
      )
    );
  }

  return React.createElement("div", { className: "tab-content" },

    // Balances row
    React.createElement("div", { className: "stats-row" },
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "DAPP Balance"),
        React.createElement("div", { className: "stat-value orange" }, dappBal)
      ),
      React.createElement("div", { className: "stat-card" },
        React.createElement("div", { className: "stat-label" }, "Pool Rate"),
        React.createElement("div", { className: "stat-value blue" },
          emissionRate, " /hr"
        )
      )
    ),

    // New stake
    React.createElement("div", { className: "card" },
      React.createElement("div", { className: "card-title" }, "New Stake"),
      React.createElement("div", { className: "input-group" },
        React.createElement("label", { className: "input-label" }, "ETH Amount"),
        React.createElement("input", {
          className:   "input-field",
          type:        "number",
          placeholder: "0.01",
          value:       ethInput,
          onChange:    e => setEthInput(e.target.value),
          min:         "0",
          step:        "0.001",
        })
      ),
      React.createElement("button", {
        className: "btn btn-green btn-full",
        onClick:   handleStake,
        disabled:  staking || !ethInput,
      },
        staking
          ? React.createElement(React.Fragment, null,
              React.createElement("span", { className: "spinner" }),
              "Staking..."
            )
          : "Stake ETH"
      )
    ),

    // Active stakes list
    React.createElement("div", { className: "card" },
      React.createElement("div", { className: "card-title" },
        `Active Stakes (${stakes.length})`
      ),
      loading
        ? React.createElement("div", { className: "empty-state" },
            React.createElement("span", { className: "spinner" }),
            " Loading..."
          )
        : stakes.length === 0
          ? React.createElement("div", { className: "empty-state" },
              "No active stakes yet. Deposit ETH above to start earning DAPP."
            )
          : stakes.map(s =>
              React.createElement("div", {
                key:       s.index,
                className: "stake-item",
              },
                React.createElement("div", { className: "stake-header" },
                  React.createElement("span", { className: "stake-id" },
                    "#", stakeId(address, s.index)
                  ),
                  React.createElement("span", {
                    className: `tier-badge ${tierClass(s.tier)}`
                  }, tierLabel(s.tier))
                ),
                React.createElement("div", { className: "stake-row" },
                  React.createElement("span", { className: "stake-meta-label" },
                    "Amount"
                  ),
                  React.createElement("span", { className: "stake-meta-value" },
                    parseFloat(s.amount).toFixed(4), " ETH"
                  )
                ),
                React.createElement("div", { className: "stake-row" },
                  React.createElement("span", { className: "stake-meta-label" },
                    "Active"
                  ),
                  React.createElement("span", { className: "stake-meta-value" },
                    daysActive(s.startTime)
                  )
                ),
                React.createElement("div", { className: "stake-row" },
                  React.createElement("span", { className: "stake-meta-label" },
                    "Pending DAPP"
                  ),
                  React.createElement("span", {
                    className: "stake-meta-value text-orange"
                  },
                    parseFloat(s.pending).toFixed(4)
                  )
                ),
                React.createElement("div", { className: "stake-actions" },
                  React.createElement("button", {
                    className: "btn btn-primary",
                    onClick:   () => handleClaim(s.index),
                    disabled:  parseFloat(s.pending) < 0.01,
                  }, "Claim"),
                  canUpgrade(s) && React.createElement("button", {
                    className: "btn btn-outline",
                    onClick:   () => handleUpgrade(s.index),
                  }, "Upgrade"),
                  React.createElement("button", {
                    className: "btn btn-danger",
                    onClick:   () => handleUnstake(s.index),
                  }, "Unstake")
                )
              )
            )
    )
  );
}

// ── LEADERBOARD TAB ───────────────────────
function LeaderboardTab({ wallet }) {
  const { provider, address } = wallet;
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(false);

  async function loadLeaderboard() {
    if (!provider) return;
    setLoading(true);
    try {
      const timer = new ethers.Contract(
        ADDRESSES.timerGame, ABI_TIMER, provider
      );
      const pool = new ethers.Contract(
        ADDRESSES.stakingPool, ABI_STAKING, provider
      );

      const count = await timer.getRegisteredCount();
      const total = count.toNumber();
      const rows  = [];

      for (let i = 0; i < total; i++) {
  try {
    const wallet = await withTimeout(timer.registeredWallets(i));
    const [, tier, duration, amount, found] =
      await withTimeout(pool.getBestStake(wallet));
    if (!found || amount.eq(0)) continue;
    rows.push({
      wallet,
      tier,
      duration: duration.toNumber(),
      amount:   ethers.utils.formatEther(amount),
    });
  } catch (e) {
    console.warn("Leaderboard entry failed, skipping:", e.message);
    continue;
  }
      }

      // Sort by ranking cascade
      rows.sort((a, b) => {
        if (a.tier !== b.tier) return b.tier - a.tier;
        if (a.duration !== b.duration) return b.duration - a.duration;
        return parseFloat(b.amount) - parseFloat(a.amount);
      });

      setEntries(rows);
    } catch (e) {
      console.warn("Leaderboard error:", e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { loadLeaderboard(); }, [provider]);

  function stakeId(addr, tier) {
    return addr.slice(2, 8).toUpperCase();
  }

  function tierBadge(t) {
    const map = { 3: "T3", 2: "T2", 1: "T1" };
    const cls = { 3: "t3", 2: "t2", 1: "t1" };
    return React.createElement("span", {
      className: `tier-badge ${cls[t] || "t1"}`
    }, map[t] || "T1");
  }

  function rankClass(i) {
    if (i === 0) return "leaderboard-row rank-1";
    if (i === 1) return "leaderboard-row rank-2";
    return "leaderboard-row";
  }

  function rankNum(i) {
    if (i === 0) return React.createElement("span", {
      className: "rank-num gold"
    }, "1st");
    if (i === 1) return React.createElement("span", {
      className: "rank-num silver"
    }, "2nd");
    return React.createElement("span", {
      className: "rank-num"
    }, `${i + 1}`);
  }

  const isOwn = (w) =>
    address && w.toLowerCase() === address.toLowerCase();

  return React.createElement("div", { className: "tab-content" },
    React.createElement("div", { className: "card" },
      React.createElement("div", { className: "card-title" },
        `Rankings (${entries.length})`
      ),
      loading
        ? React.createElement("div", { className: "empty-state" },
            React.createElement("span", { className: "spinner" }),
            " Loading..."
          )
        : entries.length === 0
          ? React.createElement("div", { className: "empty-state" },
              "No stakers registered yet. Stake ETH and push the timer to appear here."
            )
          : entries.map((e, i) =>
              React.createElement("div", {
                key:       e.wallet,
                className: rankClass(i),
              },
                rankNum(i),
                React.createElement("div", null,
                  React.createElement("div", { className: "lb-stake-id" },
                    "#", stakeId(e.wallet),
                    isOwn(e.wallet) && React.createElement("span", {
                      style: {
                        marginLeft: "6px",
                        fontSize:   "0.65rem",
                        color:      "var(--green)",
                      }
                    }, "YOU")
                  )
                ),
                tierBadge(e.tier),
                React.createElement("div", { className: "lb-amount" },
                  parseFloat(e.amount).toFixed(3), " ETH"
                )
              )
            )
    )
  );
}
// ── ROOT APP ──────────────────────────────
function App() {
  const wallet      = useWallet();
  const timer       = useTimer(wallet.provider);
  const [tab, setTab] = useState("arena");

  const { address, ethBalance, connecting, status,
          connect, disconnect } = wallet;

  function shortAddr(addr) {
    if (!addr) return "";
    return addr.slice(0, 6) + "..." + addr.slice(-4);
  }

  return React.createElement("div", { className: "app" },

    // Header
    React.createElement("header", { className: "app-header" },
      React.createElement("div", { className: "app-logo" },
        "Blockpot", React.createElement("span", null, "DAO")
      ),
      React.createElement("div", { className: "network-pill" },
        "Arbitrum Sepolia"
      )
    ),

    // Wallet bar
    React.createElement("div", {
      className: `wallet-bar ${address ? "" : "disconnected"}`
    },
      address
        ? React.createElement(React.Fragment, null,
            React.createElement("div", { className: "wallet-dot" }),
            React.createElement("div", { className: "wallet-info" },
              React.createElement("span", { className: "wallet-id" },
                shortAddr(address)
              ),
              React.createElement("span", {
                style: {
                  fontSize:   "0.72rem",
                  color:      "var(--text-muted)",
                  fontFamily: "var(--mono)",
                }
              }, ethBalance, " ETH")
            ),
            React.createElement("button", {
              className: "btn-disconnect",
              onClick:   disconnect,
            }, "Disconnect")
          )
        : React.createElement("button", {
            className: "btn-connect",
            onClick:   connect,
            disabled:  connecting,
          },
            connecting
              ? React.createElement(React.Fragment, null,
                  React.createElement("span", { className: "spinner" }),
                  " Connecting..."
                )
              : "Connect Wallet"
          )
    ),

    // Status bar
    status && React.createElement("div", {
      className: `status-bar ${status.type}`
    }, status.msg),

    // Tabs
    React.createElement("div", { className: "tabs" },
      ["arena", "stakes", "leaderboard"].map(t =>
        React.createElement("button", {
          key:       t,
          className: `tab ${tab === t ? "active" : ""}`,
          onClick:   () => setTab(t),
        },
          t === "arena"       ? "Arena"
          : t === "stakes"    ? "My Stakes"
          : "Leaderboard"
        )
      )
    ),

    // Tab content
    tab === "arena"       && React.createElement(ArenaTab, {
      wallet, timer
    }),
    tab === "stakes"      && React.createElement(MyStakesTab, {
      wallet
    }),
    tab === "leaderboard" && React.createElement(LeaderboardTab, {
      wallet
    })
  );
}

// ── RENDER ────────────────────────────────
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(React.createElement(App));
