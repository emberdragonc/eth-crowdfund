// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Campaign.sol";

/// @title CrowdfundFactory - Expressive Assurance Contract Factory
/// @author Ember 🐉 (emberclawd.eth)
/// @notice Factory for creating immutable crowdfunding campaigns
/// @dev No admin keys, no upgrades - pure on-chain logic
contract CrowdfundFactory {
    // ============ EVENTS ============
    event CampaignCreated(
        address indexed campaign,
        address indexed creator,
        string title,
        uint256 softCap,
        uint256 hardCap,
        uint256 deadline
    );

    // ============ STATE ============
    address[] public campaigns;
    mapping(address => address[]) public campaignsByCreator;

    // ============ ERRORS ============
    error InvalidParameters();

    // ============ FUNCTIONS ============

    /// @notice Create a new crowdfunding campaign
    /// @param title Campaign title
    /// @param description Campaign description
    /// @param softCap Minimum funding goal (wei)
    /// @param hardCap Maximum funding accepted (wei)
    /// @param deadline Funding deadline (unix timestamp)
    /// @param votingPeriod How long milestone voting lasts (seconds)
    /// @param milestoneDescriptions Array of milestone descriptions
    /// @param milestoneAmounts Array of amounts to release per milestone
    /// @param milestoneDeadlines Array of milestone deadlines
    /// @return campaign Address of the new campaign
    function createCampaign(
        string calldata title,
        string calldata description,
        uint256 softCap,
        uint256 hardCap,
        uint256 deadline,
        uint256 votingPeriod,
        string[] calldata milestoneDescriptions,
        uint256[] calldata milestoneAmounts,
        uint256[] calldata milestoneDeadlines
    ) external returns (address campaign) {
        if (msg.sender == address(0)) revert InvalidParameters();

        campaign = address(new Campaign(
            msg.sender,
            title,
            description,
            softCap,
            hardCap,
            deadline,
            votingPeriod,
            milestoneDescriptions,
            milestoneAmounts,
            milestoneDeadlines
        ));

        campaigns.push(campaign);
        campaignsByCreator[msg.sender].push(campaign);

        emit CampaignCreated(
            campaign,
            msg.sender,
            title,
            softCap,
            hardCap,
            deadline
        );
    }

    /// @notice Get total number of campaigns
    function getCampaignCount() external view returns (uint256) {
        return campaigns.length;
    }

    /// @notice Get campaigns by creator
    function getCampaignsByCreator(address creator) external view returns (address[] memory) {
        return campaignsByCreator[creator];
    }

    /// @notice Get all campaigns (paginated)
    /// @param offset Start index
    /// @param limit Max campaigns to return
    function getCampaigns(uint256 offset, uint256 limit) external view returns (address[] memory result) {
        uint256 total = campaigns.length;
        if (offset >= total) {
            return new address[](0);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = campaigns[i];
        }
    }
}
