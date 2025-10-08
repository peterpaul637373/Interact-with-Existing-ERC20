# 🪙 ERC20 Token Interaction Contract

A powerful Clarity smart contract that enables seamless interaction with existing SIP-010 tokens on the Stacks blockchain. This contract teaches essential concepts like token approvals, deposits, withdrawals, and batch operations.

## ✨ Features

- 🔐 **Token Approvals**: Implement secure token approval mechanisms
- 💰 **Deposit & Withdraw**: Safe token deposit and withdrawal functionality  
- 🔄 **Transfer From**: Execute transfers on behalf of other users with proper approvals
- 📦 **Batch Operations**: Process multiple deposits in a single transaction
- 🚨 **Emergency Withdraw**: Emergency withdrawal functionality for users
- ⚙️ **Fee Management**: Configurable deposit and withdrawal fees
- 🛡️ **Access Control**: Owner-only administrative functions
- ⏸️ **Pause Mechanism**: Emergency pause functionality
- 📊 **Token Support**: Add/remove supported token contracts

## 🚀 Getting Started

### Prerequisites

- Clarinet installed on your system
- Basic understanding of Clarity smart contracts
- SIP-010 compatible tokens to interact with

### Installation

1. Clone this repository into your Clarinet project
2. Deploy the contract to your preferred network
3. Add supported token contracts using the admin functions

## 📖 Usage

### For Contract Owner

#### Add Supported Token
```clarity
(contract-call? .interact-with-existing-erc20 add-supported-token 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token)
```

#### Set Fees
```clarity
(contract-call? .interact-with-existing-erc20 set-deposit-fee u100)
(contract-call? .interact-with-existing-erc20 set-withdrawal-fee u50)
```

### For Users

#### Approve Tokens
```clarity
(contract-call? .interact-with-existing-erc20 approve-token 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token 'SPENDER-ADDRESS u1000000)
```

#### Deposit Tokens
```clarity
(contract-call? .interact-with-existing-erc20 deposit-tokens 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token u500000)
```

#### Withdraw Tokens
```clarity
(contract-call? .interact-with-existing-erc20 withdraw-tokens 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token u250000)
```

#### Transfer From (with approval)
```clarity
(contract-call? .interact-with-existing-erc20 transfer-from 'SP2C2YFP12AJZB4MABJBAJ55XECVS7E4PMMZ89YZR.usda-token 'OWNER-ADDRESS 'RECIPIENT-ADDRESS u100000)
```

## 🔍 Read-Only Functions

### Check User Deposit
```clarity
(contract-call? .interact-with-existing-erc20 get-user-deposit 'USER-ADDRESS 'TOKEN-ADDRESS)
```

### Check Token Allowance
```clarity
(contract-call? .interact-with-existing-erc20 get-token-allowance 'OWNER-ADDRESS 'SPENDER-ADDRESS 'TOKEN-ADDRESS)
```

### Get Contract Information
```clarity
(contract-call? .interact-with-existing-erc20 get-contract-info)
```

## 🛠️ Key Concepts Demonstrated

### 🔐 Token Approvals
Learn how to implement and manage token approvals, allowing other addresses to spend tokens on your behalf within specified limits.

### 💸 Fee Mechanisms
Understand how to implement configurable fees for different operations, with proper calculation and deduction.

### 🔒