# Feature: Implement Revenue Sharing for Vote Token Holders

## Summary
Implement an autonomous revenue sharing system that distributes monthly dividends from vending machine sales to vote token holders proportionally to their holdings.

## Problem
The vending machine generates revenue from product sales but lacks a mechanism to distribute profits to vote token holders. Revenue accumulates in the VendingMachine contract with no automated distribution system.

## Proposed Solution

### Core Architecture
- **TreasuryDistributor Contract**: Autonomous contract with TREASURY_ROLE that manages monthly distributions
- **Revenue Split**: Stocker receives fixed percentage (e.g., 20%), remainder distributed to consumers
- **Purchase-Time Tracking**: Track buyer eligibility during vending machine purchases
- **Time-Based Cycles**: 30-day distribution cycles using block.timestamp
- **Push-Based Distribution**: Automatic transfer of dividends without user action
- **Multi-Token Support**: Distribute USDC, USDT, DAI proportionally

### Key Components

#### 1. Data Structures
```solidity
address[] public currentBuyers;                          // buyers in current cycle
mapping(address => uint256) public eligibleBalance;      // balance - lastIncludedBalance
mapping(address => uint256) public lastIncludedBalance;  // balance included in last distribution
mapping(address => bool) public isInCurrentCycle;        // track if buyer in current cycle
address public stockerAddress;                          // address receiving stocker share
uint256 public stockerShareBps = 2000;                  // 20% for stocker
uint256 public cycleLength = 30 days;                   // distribution interval
uint256 public lastCycleTimestamp;                      // when current cycle started
```

#### 2. Distribution Flow
1. **Purchase Hook**: VendingMachine notifies TreasuryDistributor on each sale
2. **Track Eligibility**: Calculate `eligibleBalance = currentBalance - lastIncludedBalance`
3. **Monthly Distribution**:
   - Claim all token balances from VendingMachine
   - Pay stocker share: `totalRevenue * stockerShareBps / 10000`
   - Distribute remainder to consumers: `(eligibleBalance / totalEligible) * consumerRevenue`
   - Transfer proportional amounts of each token
   - Update lastIncludedBalance and clear mappings
   - Reset for new cycle

#### 3. Integration Requirements
- **VendingMachine**: Add `_notifyTreasuryOnPurchase()` hook after minting
- **VoteToken**: No changes needed - uses standard ERC20Votes interface
- **Access Control**: Grant TREASURY_ROLE to TreasuryDistributor

## Benefits
- **Gas Efficient**: Only iterate active buyers, not all token holders
- **Fair Distribution**: Based on holdings minus already distributed amounts
- **Autonomous**: No manual intervention required
- **Sybil Resistant**: Physical vending constraints prevent gaming

## Implementation Tasks

### Smart Contracts
- [ ] Create TreasuryDistributor contract
- [ ] Add purchase hook to VendingMachine
- [ ] Implement cycle management logic
- [ ] Add multi-token distribution support

### Testing
- [ ] Unit tests for distribution calculations
- [ ] Integration tests with VendingMachine
- [ ] Gas consumption benchmarks
- [ ] Multi-cycle accuracy tests

### Deployment
- [ ] Deploy TreasuryDistributor
- [ ] Grant TREASURY_ROLE to distributor
- [ ] Configure allowed tokens list
- [ ] Initialize first cycle

## Acceptance Criteria
- [ ] Monthly distributions execute automatically
- [ ] Stocker receives configured percentage (e.g., 20%) of revenue
- [ ] Remaining revenue distributed proportionally to vote token holders
- [ ] Multiple payment tokens distributed correctly
- [ ] Gas costs remain reasonable for up to 1000 buyers
- [ ] No manual intervention required after deployment

## Technical Specifications
See [REVENUE_SHARING_SPEC.md](./docs/REVENUE_SHARING_SPEC.md) for detailed architecture and implementation details.

## Estimated Effort
- Development: 2-3 weeks
- Testing: 1 week
- Deployment & Verification: 2-3 days

## Dependencies
- Existing VendingMachine contract
- Existing VoteToken (ERC20Votes)
- Access to TREASURY_ROLE for configuration

## Risks & Mitigations
- **Risk**: High gas costs with many buyers
  - **Mitigation**: Batch processing, only track active participants
- **Risk**: Failed token transfers blocking distribution
  - **Mitigation**: Continue distribution even if individual transfers fail
- **Risk**: Time manipulation
  - **Mitigation**: Use reasonable time windows, require minimum cycle length

## References
- [Technical Specification](./docs/REVENUE_SHARING_SPEC.md)
- [Crowdstake.fun Cycle Management](./crowdstake.fun/src/CycleModule.sol) (inspiration)