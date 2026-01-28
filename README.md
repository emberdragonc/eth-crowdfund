# 🐉 ETH Crowdfund

**Expressive Assurance Contract Protocol for Ethereum**

An immutable, trustless crowdfunding protocol with milestone-based releases and contributor governance.

Built by [Ember](https://x.com/emberclawd) per [@ryanberckmans](https://x.com/ryanberckmans)'s spec.

## What is an Assurance Contract?

An assurance contract (like Kickstarter) works on an all-or-nothing model:
- Contributors pledge funds toward a goal
- If goal is met → funds go to project creator
- If goal is NOT met → funds return to contributors

## What Makes This "Expressive"?

Beyond simple all-or-nothing, this protocol adds:

### 🎯 Milestone-Based Releases
Funds released in stages as milestones are completed and approved by contributors.

### 🗳️ Contributor Governance
- Contributors vote on milestone completion
- Votes weighted by contribution amount
- 66% supermajority required to approve
- Failed milestones enable refunds

### 💰 Flexible Goals
- **Soft Cap**: Minimum funding required
- **Hard Cap**: Maximum funding accepted
- Excess contributions automatically refunded

### ⏰ Time-Based Conditions
- Funding deadline
- Milestone deadlines
- Voting periods

## Features

| Feature | Description |
|---------|-------------|
| **Immutable** | No admin keys, no upgrades |
| **Trustless** | Pure on-chain logic |
| **Fair Voting** | ETH-weighted, 66% threshold |
| **Early Finalization** | Votes resolve when outcome is certain |
| **Automatic Refunds** | If goal not met or milestone rejected |
| **Factory Pattern** | Anyone can create campaigns |

## How It Works

### 1. Create Campaign
```solidity
factory.createCampaign(
    "My Project",           // title
    "Building something",   // description
    10 ether,              // soft cap (minimum goal)
    20 ether,              // hard cap (maximum)
    block.timestamp + 30 days,  // funding deadline
    3 days,                // voting period per milestone
    milestoneDescriptions, // ["MVP", "Beta", "Launch"]
    milestoneAmounts,      // [4 ether, 3 ether, 3 ether]
    milestoneDeadlines     // [60 days, 90 days, 120 days]
);
```

### 2. Contribute
```solidity
campaign.contribute{value: 1 ether}();
```

### 3. Milestone Voting
```solidity
// Creator submits milestone
campaign.submitMilestone(0);

// Contributors vote
campaign.voteMilestone(0, true);  // approve
campaign.voteMilestone(0, false); // reject

// Finalize after voting period (or early if outcome certain)
campaign.finalizeMilestone(0);
```

### 4. Refunds
```solidity
// Automatic refund if goal not met or milestone rejected
campaign.claimRefund();
```

## Architecture

```
┌─────────────────────┐
│  CrowdfundFactory   │  Creates campaigns
└──────────┬──────────┘
           │ creates
           ▼
┌─────────────────────┐
│      Campaign       │  Individual campaign
├─────────────────────┤
│ • Contributions     │
│ • Milestones        │
│ • Voting            │
│ • Refunds           │
└─────────────────────┘
```

## Security

- ✅ ReentrancyGuard on all state-changing externals
- ✅ Checks-Effects-Interactions pattern
- ✅ Input validation
- ✅ No admin keys
- ✅ Immutable contracts
- ✅ 31 tests passing

Built following the [Smart Contract Development Framework](https://github.com/emberdragonc/smart-contract-framework).

## Installation

```bash
git clone https://github.com/emberdragonc/eth-crowdfund
cd eth-crowdfund
forge install
forge build
forge test
```

## Deployment

```bash
# Set your private key
export PRIVATE_KEY=0x...

# Deploy to Base Sepolia
forge script script/Deploy.s.sol --rpc-url base-sepolia --broadcast --verify

# Deploy to Base Mainnet
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
```

## Gas Costs

| Action | Gas |
|--------|-----|
| Create Campaign | ~1.5M |
| Contribute | ~95K |
| Submit Milestone | ~55K |
| Vote | ~135K |
| Claim Refund | ~50K |

## License

MIT

## Author

Built by **Ember** 🐉 ([@emberclawd](https://x.com/emberclawd))

Per spec from [@ryanberckmans](https://x.com/ryanberckmans)

---

*"Trustless crowdfunding for the next generation of builders."*
