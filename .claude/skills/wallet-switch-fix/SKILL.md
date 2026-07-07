---
name: wallet-switch-fix
description: "[AUTO-INVOKE] MUST be invoked when debugging or writing wallet connection code in any ecosystem DApp: account/wallet switching, stale signers, 'unknown account #0' (UNSUPPORTED_OPERATION) errors, Brave/tablet wallet quirks, accountsChanged handling, or dead-button states after backgrounding. Frontend-only patterns — no contract changes. Trigger: any task touching connect/disconnect flow, signer lifecycle, or mobile wallet session drops."
---

# Wallet Switch & Session Fix Skill

**Scope:** frontend / `app.js` only. No contract change, no redeployment.

**Symptoms this covers:**
- On Brave (tablet), switching account or wallet leaves the DApp showing the *old* address, a stale signer, hung approval queues, or a dead-button state after a previous WalletConnect session.
- After the browser is backgrounded on mobile, any transaction fails with `unknown account #0 (operation="getAddress", code=UNSUPPORTED_OPERATION)` while the UI still shows a connected address.

---

## Root Causes (all frontend)

1. **No `accountsChanged` handler** — the DApp never notices the switch, so `signer` and balances stay stale.
2. **Signer captured once at connect time** — mobile wallets drop the active account when the browser is backgrounded; the old signer object then has no account behind it and throws `unknown account #0` at `getAddress()`. (Confirmed live on BlockpotDAO, July 2026 — DebugHub export showed a session with `wallet: null` while the UI displayed the previous address.)
3. **Stale WalletConnect session** (Brave/tablet) — an old session lingers and blocks the new connect.
4. **Multiple providers competing** for `window.ethereum` (`window.ethereum.providers`) — Brave Wallet vs any other injected wallet.
5. **Duplicate listeners** — re-connecting adds a second `accountsChanged` handler, so events fire twice.

---

## The Fix

### A. Select the right provider explicitly (Brave-safe)

```javascript
function getInjectedProvider() {
  const eth = window.ethereum;
  if (!eth) return null;
  // When multiple wallets inject, eth.providers is an array
  if (eth.providers && eth.providers.length) {
    return eth.providers.find(p => p.isBraveWallet)
        || eth.providers.find(p => p.isMetaMask)
        || eth.providers[0];
  }
  return eth;
}
```

### B. Re-validate the wallet session at TRANSACTION time (`getFreshSigner`)

Never trust a signer captured at connect time. Every write handler starts by
rebuilding one — this is the fix for `unknown account #0`:

```javascript
async function getFreshSigner() {
  if (typeof window.ethereum === "undefined") return null;
  try {
    let accounts = await window.ethereum.request({ method: "eth_accounts" });
    if (!accounts || accounts.length === 0) {
      // Session dropped — ask wallet to re-expose accounts (reopens prompt)
      accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
    }
    if (!accounts || accounts.length === 0) {
      showStatus("Wallet session expired. Reconnect your wallet.", "error");
      return null;
    }
    const provider = new ethers.providers.Web3Provider(window.ethereum);
    const signer   = provider.getSigner();
    // refresh app state (provider/signer/address) here
    return signer;
  } catch (e) {
    DebugHub.logError("getFreshSigner", e);
    showStatus("Wallet session expired. Reconnect your wallet.", "error");
    return null;
  }
}

// Usage — top of EVERY write handler (approve/push/stake/unstake/claim/upgrade):
const s = await getFreshSigner();
if (!s) return;
const addr  = await s.getAddress();               // never use stale state address
const nonce = await s.provider.getTransactionCount(addr, "pending");
```

### C. Handle the switch — end the DebugHub session, start a fresh one

New wallet connection = new session, always. A switch must `endSession()` then `startSession()`.

```javascript
async function handleAccountsChanged(accounts) {
  // Close the old telemetry session first
  window.DebugHub.endSession();

  if (!accounts || accounts.length === 0) {
    // Wallet disconnected / locked
    resetWalletState();
    return;
  }

  currentAccount = accounts[0];
  provider = new ethers.providers.Web3Provider(injected);
  signer   = provider.getSigner();

  // Fresh session for the new wallet
  window.DebugHub.startSession("faucet", currentAccount);   // set dappName per DApp
  window.DebugHub.logCheckpoint("Wallet Switched", "pass");

  await refreshBalances();   // re-pull ETH + token balances for the new account
}

function handleChainChanged() {
  // Simplest robust behaviour — reload so provider/network state is clean
  window.location.reload();
}
```

### D. Bind listeners once (Brave fires these reliably; don't stack them)

```javascript
function bindWalletListeners() {
  if (listenersBound || !injected) return;
  injected.on("accountsChanged", handleAccountsChanged);
  injected.on("chainChanged", handleChainChanged);
  window.addEventListener("beforeunload", () => window.DebugHub.endSession());
  listenersBound = true;
}
```

In React, bind inside a `useEffect` and remove the listener in the cleanup
return — the effect re-runs on `address` change, so cleanup IS the
duplicate-listener guard.

### E. Guard the visibility-refresh path

If the app rebuilds its provider on `visibilitychange` (mobile keep-alive
pattern), check `eth_accounts` FIRST and skip the rebuild when empty —
otherwise you install a broken signer that fails later:

```javascript
const accounts = await window.ethereum.request({ method: "eth_accounts" });
if (!accounts || accounts.length === 0) return;   // don't install a dead signer
```

---

## Telemetry hooks (DebugHub)

Log these so a dropped session is visible in the dashboard instead of only
surfacing as a raw ethers error:

- `logSecurity("Wallet Session Check", "fail")` — when `eth_accounts` comes back empty at transaction time
- `logCheckpoint("Wallet Session Recovered", "pass")` — when `eth_requestAccounts` restores it
- `logSecurity("Wallet Dropped", "fail")` — on `accountsChanged` with an empty array
- `logCheckpoint("Wallet Switched", "pass")` — on account switch, AFTER `endSession()` + `startSession()`

---

## Manual Brave Recovery (when a stale session blocks connect)

Do these on the tablet **before** assuming the code is broken:

1. **Brave Shields OFF** for the DApp URL (Shields block wallet injection).
2. In Brave Wallet → the connected site → **disconnect** the DApp, then reconnect.
3. Clear the wallet's recent **activity / pending requests** — a hung request stalls the queue silently.
4. Check the wallet's **Pending Requests** (Activity tab) before restarting the browser. If a "Submitting transaction…" log appears in console but no popup, the wallet UI is hung, not the code.
5. Last resort: reload the page (forces a clean provider), or clear site data for the DApp origin.

---

## Verify After Fixing

- Switch account in Brave Wallet → DApp address + balances update with no reload of your own.
- Background the browser several minutes, return, send a transaction → wallet prompt reopens (or tx goes through), no `unknown account #0`.
- DebugHub Sessions tab shows the **old session closed** and a **new session opened** on the switch.
- No duplicate history entries (confirms listeners bound once, not stacked).
- No sessions with `wallet: null` while the UI shows a connected address.
