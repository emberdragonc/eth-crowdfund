# ETH Crowdfund - Fee Structure Planning

## Goal
All protocol fees flow to $EMBER staking contract → distributed to stakers as WETH rewards.

## Fee Options

### Option A: Success Fee Only
- **When:** Campaign reaches goal and funds are released
- **Amount:** 1-3% of total raised
- **Pros:** Only charge on success, fair
- **Cons:** No revenue from failed campaigns

### Option B: Creation Fee + Success Fee
- **Creation Fee:** 0.01-0.05 ETH flat fee to create campaign
- **Success Fee:** 1-2% of raised funds
- **Pros:** Some guaranteed revenue, discourages spam
- **Cons:** Barrier to entry

### Option C: Success Fee + Milestone Fee
- **Success Fee:** 0.5% when soft cap reached
- **Milestone Fee:** 0.5% on each milestone release
- **Pros:** Revenue aligned with project progress
- **Cons:** More complex

## Recommended: Option A (Success Fee Only)

Keep it simple for V1:
- **2% success fee** on funds raised when campaign succeeds
- Charged when creator claims funds (each milestone release)
- Fee sent directly to staking contract

### Example
- Campaign raises 10 ETH
- Milestone 1 releases 4 ETH → 0.08 ETH fee (2%)
- Milestone 2 releases 3 ETH → 0.06 ETH fee
- Milestone 3 releases 3 ETH → 0.06 ETH fee
- **Total fees:** 0.20 ETH → staking contract

## Implementation

### Contract Changes Needed

```solidity
// Add to Campaign.sol
address public immutable feeRecipient;  // Staking contract
uint256 public constant FEE_BPS = 200;  // 2% = 200 basis points

// In _finalizeMilestone, before transferring to creator:
uint256 fee = (releaseAmount * FEE_BPS) / 10000;
uint256 creatorAmount = releaseAmount - fee;

// Send fee to staking
(bool feeSent, ) = feeRecipient.call{value: fee}("");
require(feeSent, "Fee transfer failed");

// Send remainder to creator
(bool sent, ) = creator.call{value: creatorAmount}("");
require(sent, "Transfer failed");
```

### Factory Changes

```solidity
// Add to CrowdfundFactory.sol
address public immutable stakingContract;

constructor(address _stakingContract) {
    stakingContract = _stakingContract;
}

// Pass to Campaign constructor
campaign = new Campaign(
    msg.sender,
    // ... other params
    stakingContract  // feeRecipient
);
```

## Staking Contract Requirements

Need to redeploy staking with:
1. Synthetix StakingRewards (unmodified)
2. WETH as reward token (not raw ETH)
3. Ability to receive ETH and wrap to WETH
4. Or: wrapper contract that receives ETH, wraps, notifies rewards

## Flow

```
Campaign succeeds
    ↓
2% fee in ETH
    ↓
Staking contract (or wrapper)
    ↓
Wrap to WETH
    ↓
notifyRewardAmount()
    ↓
$EMBER stakers earn WETH
```

## Open Questions

1. Should fee % be configurable per campaign?
2. Should there be a fee cap?
3. Do we need a wrapper contract for ETH→WETH conversion?
4. Should failed campaigns have any fee?

## Next Steps

1. [ ] Decide on fee structure with Brian
2. [ ] Redeploy staking with Synthetix + WETH
3. [ ] Create wrapper contract if needed
4. [ ] Update Campaign.sol with fee logic
5. [ ] Update Factory with staking address
6. [ ] Test full flow on testnet
7. [ ] Audit
8. [ ] Deploy to mainnet
