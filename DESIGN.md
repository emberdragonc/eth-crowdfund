# ETH Crowdfund - Expressive Assurance Contract Protocol

## Project Request
Ryan Berckmans (@ryanberckmans) requested an Ethereum crowdfunding app with 
"sufficiently expressive assurance contract functionality."

## What is an Assurance Contract?
An assurance contract (like Kickstarter) works on an all-or-nothing model:
- Contributors pledge funds toward a goal
- If goal is met → funds go to project creator
- If goal is NOT met → funds return to contributors

## What makes it "Expressive"?
Beyond simple all-or-nothing, an expressive system adds:

### 1. Milestone-Based Releases
- Funds released in stages as milestones are hit
- Contributors can get refunds if milestones fail

### 2. Flexible Goal Types
- Soft cap: minimum viable funding
- Hard cap: maximum funding accepted
- Stretch goals: bonus milestones

### 3. Contributor Governance
- Contributors vote on milestone completion
- Supermajority required to release funds
- Emergency refund mechanism

### 4. Time-Based Conditions
- Funding deadline
- Milestone deadlines
- Vesting/lockup periods

## Core Features

### Campaign Creation
- Set funding goal (soft cap + hard cap)
- Define milestones with amounts
- Set funding deadline
- Set milestone deadlines

### Contributing
- Pledge ETH to campaign
- Track contribution amount
- Automatic refund if goal not met

### Milestone Voting
- Creator submits milestone completion
- Contributors vote (yes/no)
- If >66% approve → funds released
- If rejected → contributors can claim refund

### Refunds
- Automatic if funding goal not met
- Proportional if milestone fails
- Emergency refund with supermajority vote

## Technical Architecture

### Contracts
1. `CrowdfundFactory` - Creates new campaigns
2. `Campaign` - Individual campaign with milestones
3. (Optional) `GovernanceToken` - For weighted voting

### Security Considerations (from my audit checklist)
- [ ] SC01: Access control on milestone submissions
- [ ] SC04: Input validation on amounts/deadlines
- [ ] SC05: Reentrancy protection on withdrawals
- [ ] SC06: Check return values on transfers
- [ ] SC10: No unbounded loops (paginate contributors)

## Immutability
Per Ryan's spec, the protocol should be immutable:
- No admin keys
- No upgrades
- Pure on-chain logic

## References
- Basic assurance contract: programtheblockchain.com
- Kickstarter model
- Gitcoin Grants (quadratic funding inspiration)
