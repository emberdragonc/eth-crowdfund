// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Campaign.sol";
import "../src/CrowdfundFactory.sol";

contract CampaignTest is Test {
    CrowdfundFactory public factory;
    Campaign public campaign;
    
    address public creator = address(1);
    address public contributor1 = address(2);
    address public contributor2 = address(3);
    address public contributor3 = address(4);
    
    uint256 public softCap = 10 ether;
    uint256 public hardCap = 20 ether;
    uint256 public deadline;
    uint256 public votingPeriod = 3 days;
    
    string[] public milestoneDescs;
    uint256[] public milestoneAmounts;
    uint256[] public milestoneDeadlines;

    function setUp() public {
        factory = new CrowdfundFactory();
        deadline = block.timestamp + 30 days;
        
        // Setup milestones: 40%, 30%, 30%
        milestoneDescs = new string[](3);
        milestoneDescs[0] = "MVP Development";
        milestoneDescs[1] = "Beta Launch";
        milestoneDescs[2] = "Full Launch";
        
        milestoneAmounts = new uint256[](3);
        milestoneAmounts[0] = 4 ether;  // 40%
        milestoneAmounts[1] = 3 ether;  // 30%
        milestoneAmounts[2] = 3 ether;  // 30%
        
        milestoneDeadlines = new uint256[](3);
        milestoneDeadlines[0] = block.timestamp + 60 days;
        milestoneDeadlines[1] = block.timestamp + 90 days;
        milestoneDeadlines[2] = block.timestamp + 120 days;
        
        vm.prank(creator);
        address campaignAddr = factory.createCampaign(
            "Test Project",
            "A test crowdfunding campaign",
            softCap,
            hardCap,
            deadline,
            votingPeriod,
            milestoneDescs,
            milestoneAmounts,
            milestoneDeadlines
        );
        campaign = Campaign(campaignAddr);
        
        // Fund test accounts
        vm.deal(contributor1, 100 ether);
        vm.deal(contributor2, 100 ether);
        vm.deal(contributor3, 100 ether);
    }

    // ============ FACTORY TESTS ============
    
    function test_factory_createsCampaign() public view {
        assertEq(factory.getCampaignCount(), 1);
        assertEq(factory.campaigns(0), address(campaign));
    }
    
    function test_factory_tracksByCreator() public view {
        address[] memory creatorCampaigns = factory.getCampaignsByCreator(creator);
        assertEq(creatorCampaigns.length, 1);
        assertEq(creatorCampaigns[0], address(campaign));
    }
    
    function test_factory_pagination() public {
        // Create more campaigns
        vm.startPrank(creator);
        for (uint256 i = 0; i < 5; i++) {
            factory.createCampaign(
                "Test",
                "Test",
                softCap,
                hardCap,
                deadline,
                votingPeriod,
                milestoneDescs,
                milestoneAmounts,
                milestoneDeadlines
            );
        }
        vm.stopPrank();
        
        assertEq(factory.getCampaignCount(), 6);
        
        address[] memory page = factory.getCampaigns(2, 3);
        assertEq(page.length, 3);
    }

    // ============ CONTRIBUTION TESTS ============
    
    function test_contribute_success() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        assertEq(campaign.contributions(contributor1), 5 ether);
        assertEq(campaign.totalRaised(), 5 ether);
        assertEq(campaign.contributorCount(), 1);
    }
    
    function test_contribute_multipleContributors() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(contributor2);
        campaign.contribute{value: 3 ether}();
        
        assertEq(campaign.totalRaised(), 8 ether);
        assertEq(campaign.contributorCount(), 2);
    }
    
    function test_contribute_sameContributorMultipleTimes() public {
        vm.startPrank(contributor1);
        campaign.contribute{value: 3 ether}();
        campaign.contribute{value: 2 ether}();
        vm.stopPrank();
        
        assertEq(campaign.contributions(contributor1), 5 ether);
        assertEq(campaign.contributorCount(), 1); // Still 1
    }
    
    function test_contribute_capsAtHardCap() public {
        vm.prank(contributor1);
        campaign.contribute{value: 25 ether}();
        
        assertEq(campaign.totalRaised(), hardCap);
        assertEq(campaign.contributions(contributor1), hardCap);
        // Contributor should have received 5 ether refund
        assertEq(contributor1.balance, 80 ether);
    }
    
    function test_contribute_reachSoftCapChangesState() public {
        assertEq(uint256(campaign.state()), uint256(Campaign.CampaignState.Funding));
        
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        assertEq(uint256(campaign.state()), uint256(Campaign.CampaignState.Funded));
    }
    
    function test_contribute_revertsAfterDeadline() public {
        vm.warp(deadline + 1);
        
        vm.prank(contributor1);
        vm.expectRevert(Campaign.CampaignEnded.selector);
        campaign.contribute{value: 5 ether}();
    }
    
    function test_contribute_revertsZeroAmount() public {
        vm.prank(contributor1);
        vm.expectRevert(Campaign.InvalidAmount.selector);
        campaign.contribute{value: 0}();
    }
    
    function test_contribute_revertsAfterHardCapAndFunded() public {
        vm.prank(contributor1);
        campaign.contribute{value: 20 ether}();
        
        // After reaching hard cap, state is Funded (since 20 >= softCap of 10)
        // State check comes first, so reverts with CampaignEnded
        assertEq(uint256(campaign.state()), uint256(Campaign.CampaignState.Funded));
        
        vm.prank(contributor2);
        vm.expectRevert(Campaign.CampaignEnded.selector);
        campaign.contribute{value: 1 ether}();
    }
    
    function test_contribute_revertsAtHardCapDuringFunding() public {
        // Contribute just under soft cap first
        vm.prank(contributor1);
        campaign.contribute{value: 9 ether}();
        
        // Still in Funding state
        assertEq(uint256(campaign.state()), uint256(Campaign.CampaignState.Funding));
        
        // Fill to hard cap
        vm.prank(contributor2);
        campaign.contribute{value: 11 ether}();
        
        // Now at hard cap and Funded
        assertEq(campaign.totalRaised(), hardCap);
        
        // Next contribution fails with HardCapReached? No - state is now Funded
        // So it will fail with CampaignEnded
        vm.prank(contributor3);
        vm.expectRevert(Campaign.CampaignEnded.selector);
        campaign.contribute{value: 1 ether}();
    }

    // ============ REFUND TESTS ============
    
    function test_refund_afterFailedCampaign() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        // Warp past deadline without reaching goal
        vm.warp(deadline + 1);
        
        uint256 balanceBefore = contributor1.balance;
        
        vm.prank(contributor1);
        campaign.claimRefund();
        
        assertEq(contributor1.balance, balanceBefore + 5 ether);
    }
    
    function test_refund_revertsIfNoContribution() public {
        vm.warp(deadline + 1);
        
        vm.prank(contributor1);
        vm.expectRevert(Campaign.NoRefundAvailable.selector);
        campaign.claimRefund();
    }
    
    function test_refund_revertsIfGoalReached() public {
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        vm.prank(contributor1);
        vm.expectRevert(Campaign.NoRefundAvailable.selector);
        campaign.claimRefund();
    }

    // ============ MILESTONE TESTS ============
    
    function test_milestone_submitSuccess() public {
        // Fund the campaign
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        // Creator submits milestone
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        (,,, Campaign.MilestoneStatus status,,,) = campaign.getMilestone(0);
        assertEq(uint256(status), uint256(Campaign.MilestoneStatus.Voting));
    }
    
    function test_milestone_submitRevertsIfNotCreator() public {
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        vm.prank(contributor1);
        vm.expectRevert(Campaign.NotContributor.selector);
        campaign.submitMilestone(0);
    }
    
    function test_milestone_submitRevertsIfNotFunded() public {
        vm.prank(creator);
        vm.expectRevert(Campaign.GoalNotReached.selector);
        campaign.submitMilestone(0);
    }
    
    function test_milestone_voteApprove() public {
        // Fund with multiple contributors so early finalization doesn't trigger
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(contributor2);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        // Only contributor1 votes (50%) - not enough for early finalization
        vm.prank(contributor1);
        campaign.voteMilestone(0, true);
        
        (,,,, uint256 votesFor,,) = campaign.getMilestone(0);
        assertEq(votesFor, 5 ether);
    }
    
    function test_milestone_voteReject() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(contributor2);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        vm.prank(contributor1);
        campaign.voteMilestone(0, false);
        
        (,,,,, uint256 votesAgainst,) = campaign.getMilestone(0);
        assertEq(votesAgainst, 5 ether);
    }
    
    function test_milestone_cannotVoteTwice() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(contributor2);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        vm.startPrank(contributor1);
        campaign.voteMilestone(0, true);
        
        vm.expectRevert(Campaign.AlreadyVoted.selector);
        campaign.voteMilestone(0, true);
        vm.stopPrank();
    }
    
    function test_milestone_approvalReleasesFunds() public {
        // Single contributor - will trigger early finalization
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        uint256 creatorBalanceBefore = creator.balance;
        
        // Vote triggers early finalization since 100% > 66%
        vm.prank(contributor1);
        campaign.voteMilestone(0, true);
        
        // Milestone should already be approved due to early finalization
        (,,, Campaign.MilestoneStatus status,,,) = campaign.getMilestone(0);
        assertEq(uint256(status), uint256(Campaign.MilestoneStatus.Approved));
        assertEq(creator.balance, creatorBalanceBefore + 4 ether);
        assertEq(campaign.totalReleased(), 4 ether);
        assertEq(campaign.currentMilestone(), 1);
    }
    
    function test_milestone_rejectionEnablesRefund() public {
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        // Vote to reject - triggers early finalization since 100% reject
        vm.prank(contributor1);
        campaign.voteMilestone(0, false);
        
        (,,, Campaign.MilestoneStatus status,,,) = campaign.getMilestone(0);
        assertEq(uint256(status), uint256(Campaign.MilestoneStatus.Rejected));
        
        // Contributor can now claim refund
        uint256 refundAmount = campaign.getRefundAmount(contributor1);
        assertEq(refundAmount, 10 ether);
    }
    
    function test_milestone_allApprovedCompleteCampaign() public {
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        // Approve all 3 milestones - each vote triggers early finalization
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(creator);
            campaign.submitMilestone(i);
            
            vm.prank(contributor1);
            campaign.voteMilestone(i, true);
            // Milestone automatically finalized
        }
        
        assertEq(uint256(campaign.state()), uint256(Campaign.CampaignState.Completed));
        assertEq(campaign.totalReleased(), 10 ether);
    }

    // ============ VIEW FUNCTION TESTS ============
    
    function test_getCampaignInfo() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        (
            address _creator,
            string memory _title,
            uint256 _softCap,
            uint256 _hardCap,
            uint256 _deadline,
            uint256 _totalRaised,
            uint256 _totalReleased,
            uint256 _contributorCount,
            Campaign.CampaignState _state
        ) = campaign.getCampaignInfo();
        
        assertEq(_creator, creator);
        assertEq(_title, "Test Project");
        assertEq(_softCap, softCap);
        assertEq(_hardCap, hardCap);
        assertEq(_deadline, deadline);
        assertEq(_totalRaised, 5 ether);
        assertEq(_totalReleased, 0);
        assertEq(_contributorCount, 1);
        assertEq(uint256(_state), uint256(Campaign.CampaignState.Funding));
    }
    
    function test_getMilestoneCount() public view {
        assertEq(campaign.getMilestoneCount(), 3);
    }
    
    function test_isGoalReached() public {
        assertFalse(campaign.isGoalReached());
        
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        assertTrue(campaign.isGoalReached());
    }

    // ============ EDGE CASE TESTS ============
    
    function test_multipleContributorsVoting() public {
        // 3 contributors with different weights
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();  // 50%
        
        vm.prank(contributor2);
        campaign.contribute{value: 3 ether}();  // 30%
        
        vm.prank(contributor3);
        campaign.contribute{value: 2 ether}();  // 20%
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        // contributor1 (50%) approves first - not enough alone
        vm.prank(contributor1);
        campaign.voteMilestone(0, true);
        
        // Still in voting
        (,,, Campaign.MilestoneStatus status1,,,) = campaign.getMilestone(0);
        assertEq(uint256(status1), uint256(Campaign.MilestoneStatus.Voting));
        
        // contributor2 (30%) rejects
        vm.prank(contributor2);
        campaign.voteMilestone(0, false);
        
        // contributor3 (20%) approves = 70% approve > 66%
        vm.prank(contributor3);
        campaign.voteMilestone(0, true);
        
        // Should be approved now via early finalization
        (,,, Campaign.MilestoneStatus status2,,,) = campaign.getMilestone(0);
        assertEq(uint256(status2), uint256(Campaign.MilestoneStatus.Approved));
    }
    
    function test_finalizeMilestoneAfterVotingPeriod() public {
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(contributor2);
        campaign.contribute{value: 5 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        // Only contributor1 votes (50%) - not enough for early finalization
        vm.prank(contributor1);
        campaign.voteMilestone(0, true);
        
        // Warp past voting period
        vm.warp(block.timestamp + votingPeriod + 1);
        
        // Anyone can finalize
        campaign.finalizeMilestone(0);
        
        // 50% votes for, 0% against = 100% approval rate, passes
        (,,, Campaign.MilestoneStatus status,,,) = campaign.getMilestone(0);
        assertEq(uint256(status), uint256(Campaign.MilestoneStatus.Approved));
    }
    
    function test_noVotesDefaultsToApproved() public {
        vm.prank(contributor1);
        campaign.contribute{value: 10 ether}();
        
        vm.prank(creator);
        campaign.submitMilestone(0);
        
        // No votes cast
        vm.warp(block.timestamp + votingPeriod + 1);
        
        campaign.finalizeMilestone(0);
        
        // Default to approved (trust creator)
        (,,, Campaign.MilestoneStatus status,,,) = campaign.getMilestone(0);
        assertEq(uint256(status), uint256(Campaign.MilestoneStatus.Approved));
    }

    // ============ FUZZ TESTS ============
    
    function testFuzz_contribute(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        
        vm.deal(contributor1, amount);
        vm.prank(contributor1);
        campaign.contribute{value: amount}();
        
        assertTrue(campaign.contributions(contributor1) <= hardCap);
        assertTrue(campaign.totalRaised() <= hardCap);
    }
}
