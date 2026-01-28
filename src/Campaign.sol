// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Campaign - Expressive Assurance Contract
/// @author Ember 🐉 (emberclawd.eth)
/// @notice A milestone-based crowdfunding campaign with contributor governance
/// @dev Implements expressive assurance contract pattern per Ryan Berckmans' spec
contract Campaign is ReentrancyGuard {
    // ============ ERRORS ============
    error CampaignEnded();
    error CampaignNotEnded();
    error GoalNotReached();
    error GoalAlreadyReached();
    error MilestoneNotPending();
    error MilestoneVotingActive();
    error MilestoneVotingEnded();
    error AlreadyVoted();
    error NotContributor();
    error InvalidMilestone();
    error NoRefundAvailable();
    error TransferFailed();
    error InvalidAmount();
    error InvalidDeadline();
    error HardCapReached();
    error ZeroAddress();

    // ============ EVENTS ============
    event Contributed(address indexed contributor, uint256 amount, uint256 totalContribution);
    event RefundClaimed(address indexed contributor, uint256 amount);
    event MilestoneSubmitted(uint256 indexed milestoneId, string description);
    event MilestoneVoted(uint256 indexed milestoneId, address indexed voter, bool approve, uint256 weight);
    event MilestoneApproved(uint256 indexed milestoneId, uint256 amountReleased);
    event MilestoneRejected(uint256 indexed milestoneId);
    event FundsReleased(address indexed creator, uint256 amount);
    event EmergencyRefundTriggered();

    // ============ STRUCTS ============
    struct Milestone {
        string description;
        uint256 amount;          // Amount to release if approved
        uint256 deadline;        // Deadline for completion
        MilestoneStatus status;
        uint256 votesFor;        // ETH-weighted votes for approval
        uint256 votesAgainst;    // ETH-weighted votes against
        uint256 votingDeadline;  // When voting ends
    }

    enum MilestoneStatus {
        Pending,
        Voting,
        Approved,
        Rejected
    }

    enum CampaignState {
        Funding,      // Accepting contributions
        Funded,       // Goal reached, milestones in progress
        Failed,       // Goal not reached by deadline
        Completed,    // All milestones approved
        Cancelled     // Emergency refund triggered
    }

    // ============ STATE ============
    address public immutable creator;
    string public title;
    string public description;
    
    uint256 public immutable softCap;      // Minimum funding goal
    uint256 public immutable hardCap;      // Maximum funding accepted
    uint256 public immutable deadline;     // Funding deadline
    uint256 public immutable votingPeriod; // How long voting lasts (seconds)
    
    uint256 public totalRaised;
    uint256 public totalReleased;
    uint256 public contributorCount;
    
    CampaignState public state;
    
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public refundsClaimed;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    Milestone[] public milestones;
    uint256 public currentMilestone;

    // ============ CONSTANTS ============
    uint256 public constant APPROVAL_THRESHOLD = 66; // 66% required to approve
    uint256 public constant EMERGENCY_THRESHOLD = 75; // 75% to trigger emergency refund
    uint256 public constant MIN_VOTING_PERIOD = 1 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;

    // ============ CONSTRUCTOR ============
    constructor(
        address _creator,
        string memory _title,
        string memory _description,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _deadline,
        uint256 _votingPeriod,
        string[] memory _milestoneDescriptions,
        uint256[] memory _milestoneAmounts,
        uint256[] memory _milestoneDeadlines
    ) {
        if (_creator == address(0)) revert ZeroAddress();
        if (_softCap == 0) revert InvalidAmount();
        if (_hardCap < _softCap) revert InvalidAmount();
        if (_deadline <= block.timestamp) revert InvalidDeadline();
        if (_votingPeriod < MIN_VOTING_PERIOD || _votingPeriod > MAX_VOTING_PERIOD) {
            revert InvalidDeadline();
        }
        if (_milestoneDescriptions.length != _milestoneAmounts.length) revert InvalidMilestone();
        if (_milestoneDescriptions.length != _milestoneDeadlines.length) revert InvalidMilestone();
        if (_milestoneDescriptions.length == 0) revert InvalidMilestone();
        
        // Verify milestone amounts sum to soft cap
        uint256 totalMilestoneAmount;
        for (uint256 i = 0; i < _milestoneAmounts.length; i++) {
            if (_milestoneAmounts[i] == 0) revert InvalidAmount();
            totalMilestoneAmount += _milestoneAmounts[i];
        }
        if (totalMilestoneAmount != _softCap) revert InvalidAmount();
        
        creator = _creator;
        title = _title;
        description = _description;
        softCap = _softCap;
        hardCap = _hardCap;
        deadline = _deadline;
        votingPeriod = _votingPeriod;
        state = CampaignState.Funding;
        
        // Create milestones
        for (uint256 i = 0; i < _milestoneDescriptions.length; i++) {
            milestones.push(Milestone({
                description: _milestoneDescriptions[i],
                amount: _milestoneAmounts[i],
                deadline: _milestoneDeadlines[i],
                status: MilestoneStatus.Pending,
                votesFor: 0,
                votesAgainst: 0,
                votingDeadline: 0
            }));
        }
    }

    // ============ CONTRIBUTE ============
    
    /// @notice Contribute ETH to the campaign
    function contribute() external payable nonReentrant {
        if (state != CampaignState.Funding) revert CampaignEnded();
        if (block.timestamp >= deadline) revert CampaignEnded();
        if (msg.value == 0) revert InvalidAmount();
        if (totalRaised >= hardCap) revert HardCapReached();
        
        uint256 contribution = msg.value;
        
        // Cap contribution at hard cap
        if (totalRaised + contribution > hardCap) {
            uint256 excess = (totalRaised + contribution) - hardCap;
            contribution = msg.value - excess;
            // Refund excess
            (bool sent, ) = msg.sender.call{value: excess}("");
            if (!sent) revert TransferFailed();
        }
        
        if (contributions[msg.sender] == 0) {
            contributorCount++;
        }
        
        contributions[msg.sender] += contribution;
        totalRaised += contribution;
        
        emit Contributed(msg.sender, contribution, contributions[msg.sender]);
        
        // Check if soft cap reached
        if (totalRaised >= softCap && state == CampaignState.Funding) {
            state = CampaignState.Funded;
        }
    }

    // ============ REFUNDS ============
    
    /// @notice Claim refund if campaign failed or milestone rejected
    function claimRefund() external nonReentrant {
        _updateState();
        
        uint256 refundAmount = getRefundAmount(msg.sender);
        if (refundAmount == 0) revert NoRefundAvailable();
        
        refundsClaimed[msg.sender] += refundAmount;
        
        (bool sent, ) = msg.sender.call{value: refundAmount}("");
        if (!sent) revert TransferFailed();
        
        emit RefundClaimed(msg.sender, refundAmount);
    }
    
    /// @notice Calculate refund amount for a contributor
    function getRefundAmount(address contributor) public view returns (uint256) {
        uint256 contributed = contributions[contributor];
        if (contributed == 0) return 0;
        
        uint256 alreadyClaimed = refundsClaimed[contributor];
        
        // If campaign failed (didn't reach soft cap), full refund
        if (state == CampaignState.Failed || state == CampaignState.Cancelled) {
            uint256 refundable = contributed - alreadyClaimed;
            // Pro-rata based on remaining balance
            uint256 remainingBalance = address(this).balance;
            uint256 totalRefundable = totalRaised - totalReleased;
            if (totalRefundable > 0) {
                return (refundable * remainingBalance) / totalRefundable;
            }
            return 0;
        }
        
        // If milestone rejected, partial refund for unreleased funds
        if (state == CampaignState.Funded) {
            // Check if current milestone was rejected
            if (currentMilestone < milestones.length && 
                milestones[currentMilestone].status == MilestoneStatus.Rejected) {
                uint256 unreleased = totalRaised - totalReleased;
                uint256 contributorShare = (contributed * unreleased) / totalRaised;
                return contributorShare > alreadyClaimed ? contributorShare - alreadyClaimed : 0;
            }
        }
        
        return 0;
    }

    // ============ MILESTONES ============
    
    /// @notice Creator submits a milestone for approval
    function submitMilestone(uint256 milestoneId) external {
        if (msg.sender != creator) revert NotContributor();
        if (state != CampaignState.Funded) revert GoalNotReached();
        if (milestoneId != currentMilestone) revert InvalidMilestone();
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        
        Milestone storage m = milestones[milestoneId];
        if (m.status != MilestoneStatus.Pending) revert MilestoneNotPending();
        
        m.status = MilestoneStatus.Voting;
        m.votingDeadline = block.timestamp + votingPeriod;
        
        emit MilestoneSubmitted(milestoneId, m.description);
    }
    
    /// @notice Vote on a milestone
    /// @param milestoneId The milestone to vote on
    /// @param approve True to approve, false to reject
    function voteMilestone(uint256 milestoneId, bool approve) external {
        if (contributions[msg.sender] == 0) revert NotContributor();
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        
        Milestone storage m = milestones[milestoneId];
        if (m.status != MilestoneStatus.Voting) revert MilestoneNotPending();
        if (block.timestamp >= m.votingDeadline) revert MilestoneVotingEnded();
        if (hasVoted[milestoneId][msg.sender]) revert AlreadyVoted();
        
        hasVoted[milestoneId][msg.sender] = true;
        uint256 weight = contributions[msg.sender];
        
        if (approve) {
            m.votesFor += weight;
        } else {
            m.votesAgainst += weight;
        }
        
        emit MilestoneVoted(milestoneId, msg.sender, approve, weight);
        
        // Check if milestone can be finalized early
        _tryFinalizeMilestone(milestoneId);
    }
    
    /// @notice Finalize a milestone after voting ends
    function finalizeMilestone(uint256 milestoneId) external {
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        
        Milestone storage m = milestones[milestoneId];
        if (m.status != MilestoneStatus.Voting) revert MilestoneNotPending();
        if (block.timestamp < m.votingDeadline) revert MilestoneVotingActive();
        
        _finalizeMilestone(milestoneId);
    }
    
    function _tryFinalizeMilestone(uint256 milestoneId) internal {
        Milestone storage m = milestones[milestoneId];
        uint256 totalVotes = m.votesFor + m.votesAgainst;
        
        // Can finalize early if threshold is definitively met or rejected
        if (totalVotes == 0) return;
        
        uint256 remainingVotes = totalRaised - totalVotes;
        
        // Check if approval is guaranteed (even if all remaining vote against)
        // votesFor / (votesFor + votesAgainst + remainingVotes) >= 66%
        // votesFor * 100 >= 66 * totalRaised
        bool guaranteedApproval = (m.votesFor * 100) >= (APPROVAL_THRESHOLD * totalRaised);
        
        // Check if rejection is guaranteed (even if all remaining vote for)
        // (votesFor + remainingVotes) / totalRaised < 66%
        bool guaranteedRejection = ((m.votesFor + remainingVotes) * 100) < (APPROVAL_THRESHOLD * totalRaised);
        
        if (guaranteedApproval || guaranteedRejection) {
            _finalizeMilestone(milestoneId);
        }
    }
    
    function _finalizeMilestone(uint256 milestoneId) internal {
        Milestone storage m = milestones[milestoneId];
        uint256 totalVotes = m.votesFor + m.votesAgainst;
        
        // Default to approved if no votes (trust the creator)
        bool approved = totalVotes == 0 || (m.votesFor * 100) / totalVotes >= APPROVAL_THRESHOLD;
        
        if (approved) {
            m.status = MilestoneStatus.Approved;
            uint256 releaseAmount = m.amount;
            
            // Don't release more than available
            if (releaseAmount > address(this).balance) {
                releaseAmount = address(this).balance;
            }
            
            totalReleased += releaseAmount;
            currentMilestone++;
            
            (bool sent, ) = creator.call{value: releaseAmount}("");
            if (!sent) revert TransferFailed();
            
            emit MilestoneApproved(milestoneId, releaseAmount);
            emit FundsReleased(creator, releaseAmount);
            
            // Check if all milestones complete
            if (currentMilestone >= milestones.length) {
                state = CampaignState.Completed;
            }
        } else {
            m.status = MilestoneStatus.Rejected;
            emit MilestoneRejected(milestoneId);
            // Contributors can now claim refunds for remaining funds
        }
    }

    // ============ STATE MANAGEMENT ============
    
    function _updateState() internal {
        if (state == CampaignState.Funding && block.timestamp >= deadline) {
            if (totalRaised >= softCap) {
                state = CampaignState.Funded;
            } else {
                state = CampaignState.Failed;
            }
        }
    }
    
    /// @notice Get current campaign state (updates if needed)
    function getState() external returns (CampaignState) {
        _updateState();
        return state;
    }
    
    /// @notice Get milestone count
    function getMilestoneCount() external view returns (uint256) {
        return milestones.length;
    }
    
    /// @notice Get milestone details
    function getMilestone(uint256 milestoneId) external view returns (
        string memory desc,
        uint256 amount,
        uint256 milestoneDeadline,
        MilestoneStatus status,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 votingDeadline
    ) {
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        Milestone storage m = milestones[milestoneId];
        return (
            m.description,
            m.amount,
            m.deadline,
            m.status,
            m.votesFor,
            m.votesAgainst,
            m.votingDeadline
        );
    }
    
    /// @notice Check if campaign reached its goal
    function isGoalReached() external view returns (bool) {
        return totalRaised >= softCap;
    }
    
    /// @notice Get campaign info
    function getCampaignInfo() external view returns (
        address _creator,
        string memory _title,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _deadline,
        uint256 _totalRaised,
        uint256 _totalReleased,
        uint256 _contributorCount,
        CampaignState _state
    ) {
        return (
            creator,
            title,
            softCap,
            hardCap,
            deadline,
            totalRaised,
            totalReleased,
            contributorCount,
            state
        );
    }
}
