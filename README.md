# StablesendPay

**A USDC payments rail on Arc for Southeast Asia.**
Programmable Money Hackathon (Build on Arc) · DeFi Track.

StablesendPay extends [Stablesend](https://stablesend.xyz) — a creator-tipping dApp — into a
general programmable-money layer with three primitives:

| Function | What it does |
|---|---|
| `payTo` | Direct 1-to-1 USDC payment with an on-chain memo |
| `batchPay` | Pay **many recipients in a single transaction** (payroll / vendor & driver payouts) |
| `createRequest` / `payRequest` | On-chain invoices anyone can settle |

Pull-payment ledger, hard-capped 5% fee, handle registry, `ReentrancyGuard`, `SafeERC20`.

## Why

Cross-border payments in SEA — freight vendors, drivers, and creators — still run on bank
transfers: 2–7 day settlement, FX spread, manual reconciliation. On Arc, USDC is the native
gas token: settlement is sub-second and fees are denominated in dollars. `batchPay` turns
dozens of bank wires into one confirmation.

## Stack

- Solidity 0.8.24 · OpenZeppelin 5.1 · Foundry
- Arc Testnet — Chain ID `5042002`, RPC `https://rpc.testnet.arc.network`
- Native USDC `0x3600000000000000000000000000000000000000`
- Frontend: Next.js 14 + wagmi/viem + Privy (see `frontend/`)

## Build & test

\`\`\`bash
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0   # if lib/ is empty
forge build
forge test -vv        # 14/14 passing
\`\`\`

## Deploy (Arc Testnet)

\`\`\`bash
export PRIVATE_KEY=0x...        # never commit this
forge script script/DeployStablesendPay.s.sol \
  --rpc-url https://rpc.testnet.arc.network --broadcast -vvvv
\`\`\`

## Layout

\`\`\`
src/StablesendPay.sol              # contract
test/StablesendPay.t.sol           # 14 Foundry tests
script/DeployStablesendPay.s.sol   # Arc Testnet deploy
frontend/BatchPayForm.tsx          # /batch page - paste rows, approve, disburse
HACKATHON.md                       # pitch + submission plan
\`\`\`

## Team

Truong Khang — Arc Architect (Tier 1) · builder & VN/SEA storyteller.

MIT License.
