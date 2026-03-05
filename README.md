# 🌳 Merkle Airdrop

<div align="center">

![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.24-363636?style=for-the-badge&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-gray?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABmJLR0QA/wD/AP+gvaeTAAAAoUlEQVQokWNgGAWkgv///w8kJSX9JxcmI6MAAAAbklEQVQoz2NgGAWkgv///w8kJSX9JxcmI6MAAAAbklEQVQoz2NgGAWkgv///w8kJSX9JxcmI6MAAAA=)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5-4E5EE4?style=for-the-badge&logo=openzeppelin)

**A gas-efficient ERC20 token airdrop system powered by Merkle proofs and EIP-712 typed signatures.**

*Distribute tokens at scale — without the gas nightmare.*

</div>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [How It Works](#-how-it-works)
- [Core Concepts](#-core-concepts)
  - [Merkle Proofs](#-merkle-proofs)
  - [EIP-712 Structured Data Signing](#-eip-712-structured-data-signing)
  - [Gasless Claims](#-signature-verification--gasless-claims)
  - [Claim Security](#-claim-security)
- [Key Features](#-key-features)
- [Project Structure](#-project-structure)
- [Usage](#-usage)
- [Dependencies](#-dependencies)

---

## 🔭 Overview

This project implements a secure airdrop mechanism for the **EYES** ERC20 token. Instead of sending tokens to every eligible address individually (which is expensive on-chain), the contract stores a single **Merkle root** on-chain. Eligible users prove their inclusion by submitting a Merkle proof along with an **EIP-712 signature**, allowing anyone — including a relayer — to submit the claim transaction on their behalf.

```
┌──────────────────────────────────────────────────────────────────┐
│                      AIRDROP OVERVIEW                            │
├─────────────────────────┬────────────────────────────────────────┤
│         Off-Chain       │             On-Chain                   │
│                         │                                        │
│  Build Merkle Tree ───► │  Store Merkle Root (bytes32)           │
│  Sign EIP-712 msg  ───► │  Verify Signature (ECDSA)              │
│  Generate Proof    ───► │  Verify Merkle Proof                   │
│                         │  Transfer EYES Tokens  ──► User        │
└─────────────────────────┴────────────────────────────────────────┘
```

---

## ⚙️ How It Works

```
  ELIGIBLE USER                  RELAYER                   CONTRACT
       │                            │                          │
       │  1. Sign EIP-712 msg       │                          │
       │  (account, amount) ──────► │                          │
       │                            │                          │
       │                            │  2. claim(              │
       │                            │       account,           │
       │                            │       amount,            │
       │                            │       merkleProof,       │
       │                            │       v, r, s     )─────►│
       │                            │                          │
       │                            │           3. Verify sig  │
       │                            │           4. Verify proof│
       │                            │           5. Mark claimed│
       │◄───────────────────────────┼──── 6. Transfer EYES ───│
       │                            │                          │
  Receives tokens      Gas paid by relayer          State updated
```

> The user **never pays gas**. A relayer submits on their behalf and the tokens always land in the correct wallet.

---

## 🧠 Core Concepts

### 🌿 Merkle Proofs

A Merkle tree is a binary hash tree where each **leaf** represents an eligible `(address, amount)` pair. Only the **root hash** is stored on-chain, making the contract extremely gas-efficient regardless of how many addresses are eligible.

```
                     ┌──────────────┐
                     │  Merkle Root │  ◄── stored on-chain (32 bytes)
                     └──────┬───────┘
                    ┌───────┴────────┐
               ┌────┴────┐      ┌────┴────┐
               │  H(A+B) │      │  H(C+D) │
               └────┬────┘      └────┬────┘
             ┌──────┴──────┐  ┌──────┴──────┐
          ┌──┴──┐       ┌──┴──┐  ┌──┴──┐  ┌──┴──┐
          │  A  │       │  B  │  │  C  │  │  D  │
          └─────┘       └─────┘  └─────┘  └─────┘
         (addr,amt)  (addr,amt) (addr,amt) (addr,amt)
            leaf         leaf      leaf       leaf
```

When a user wants to claim, they provide:
- Their **address and amount** (the leaf data)
- A **Merkle proof** (an array of sibling hashes from the leaf to the root)

The contract recomputes the root from the leaf and proof, then checks it against the stored root. If they match, the claim is valid.

> 🔐 **Double hashing** — Each leaf is hashed twice:
> ```solidity
> keccak256(bytes.concat(keccak256(abi.encode(account, amount))))
> ```
> This prevents **second preimage attacks** on the Merkle tree.

---

### ✍️ EIP-712 Structured Data Signing

[EIP-712](https://eips.ethereum.org/EIPS/eip-712) defines a standard for signing typed, structured data. Instead of signing an opaque hash, signers see a **human-readable representation** of what they are signing in their wallet.

The contract defines a **domain separator**:

| Field | Value |
|---|---|
| Name | `Merkle Airdrop` |
| Version | `1.0.0` |

And a **struct type**:
```
AirdropClaim(address account, uint256 amount)
```

This ensures signatures are:

| Property | Guarantee |
|---|---|
| 🔗 **Domain-bound** | A signature for this contract cannot be replayed on a different contract or chain |
| 👁️ **Human-readable** | Wallets display the claim details (account, amount) clearly before signing |
| 🔒 **Type-safe** | The struct layout is encoded into the signature hash |

---

### ⛽ Signature Verification & Gasless Claims

The claim function accepts `(v, r, s)` ECDSA signature components. This design enables **gasless claiming**:

```
  User                           Relayer                    Chain
  ────                           ───────                    ─────
  Sign off-chain  ──── sig ────► Submit tx + pay gas ────► Verified ✓
                                                            Tokens → User ✓
```

The tokens **always go to the rightful owner** regardless of who calls the function. This is ideal for:
- 📱 Users with no ETH for gas
- 🤖 Automated relayer networks
- 🏢 Protocols sponsoring gas for their users

---

### 🛡️ Claim Security

| Mechanism | Description |
|---|---|
| 🔂 **Single-use claims** | A mapping tracks which addresses have already claimed, preventing double-spending |
| ✅ **Checks-Effects-Interactions** | Validates all inputs → updates state → transfers tokens (CEI pattern) |
| 🧩 **SafeERC20** | Uses OpenZeppelin's `SafeERC20` to handle non-standard ERC20 implementations safely |

---

## ✨ Key Features

- ⚡ **Gas-efficient** — only a single `bytes32` Merkle root stored on-chain
- 🆓 **Gasless claiming** — via EIP-712 signatures and relayer support
- 🔐 **Double-hashed leaves** — to prevent second preimage attacks
- 🔄 **CEI pattern** — Checks-Effects-Interactions for reentrancy safety
- 🧩 **SafeERC20** — robust token transfers for all ERC20 variants
- 📌 **Immutable state variables** — gas optimization at every call
- 🧪 **Comprehensive test suite** — full coverage with Foundry

---

## 📁 Project Structure

```
Merkle Airdrop/
├── src/
│   ├── Merkle_Airdrop.sol         ← Core airdrop contract (Merkle + EIP-712)
│   └── EyesToken.sol              ← EYES ERC20 token
├── script/
│   └── DeployMerkleAirdrop.s.sol  ← Foundry deployment script
├── test/
│   └── MerkleAirdrop.t.sol        ← Unit tests
└── lib/
    ├── forge-std/                  ← Foundry standard library
    └── openzeppelin-contracts/     ← OpenZeppelin v5
```

---

## 🚀 Usage

### 🔨 Build

```shell
forge build
```

### 🧪 Test

```shell
forge test
```

### 🔍 Test with Verbosity

```shell
forge test -vvvv
```

### 📡 Deploy

```shell
MERKLE_ROOT=0x... forge script script/DeployMerkleAirdrop.s.sol:DeployMerkleAirdrop \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

---

## 📦 Dependencies

| Dependency | Purpose |
|---|---|
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | `ERC20`, `MerkleProof`, `EIP712`, `ECDSA`, `SafeERC20` |
| [Foundry](https://book.getfoundry.sh/) | Build, test, and deploy framework |

---

## 👤 Author

**Moin Shahid**

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

<div align="center">

*Built with [Foundry](https://getfoundry.sh/) · OpenZeppelin Contracts v5 · Solidity ^0.8.24*

</div>
