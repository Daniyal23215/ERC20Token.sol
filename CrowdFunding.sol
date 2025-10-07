# CrowdFunding.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Decentralized Crowdfunding (Kickstarter-like) for Remix VM
/// @notice Create campaigns, contribute ETH, creators withdraw if goal met, backers refund if not met.
/// @dev Uses mapping inside struct for contributions. NOT audited for production but fine for learning/testing.

contract Crowdfunding {
    /* ========== STATE ========== */

    struct Campaign {
        address payable creator;
        uint256 goal;            // funding goal in wei
        uint256 pledged;         // total pledged so far
        uint256 deadline;        // timestamp (seconds)
        bool withdrawn;          // whether creator already withdrew
    }

    uint256 public campaignCount;
    mapping(uint256 => Campaign) public campaigns;
    // contributions[campaignId][backer] => amount
    mapping(uint256 => mapping(address => uint256)) private contributions;

    bool private locked; // reentrancy guard

    /* ========== EVENTS ========== */

    event CampaignCreated(
        uint256 indexed id,
        address indexed creator,
        uint256 goal,
        uint256 deadline
    );

    event ContributionMade(
        uint256 indexed id,
        address indexed backer,
        uint256 amount
    );

    event CreatorWithdrawn(
        uint256 indexed id,
        address indexed creator,
        uint256 amount
    );

    event RefundClaimed(
        uint256 indexed id,
        address indexed backer,
        uint256 amount
    );

    /* ========== MODIFIERS ========== */

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    modifier campaignExists(uint256 _id) {
        require(_id > 0 && _id <= campaignCount, "Campaign does not exist");
        _;
    }

    /* ========== CORE FUNCTIONS ========== */

    /// @notice Create a new crowdfunding campaign.
    /// @param _goal Funding goal in wei.
    /// @param _durationSeconds Duration from now in seconds (must be > 0).
    /// @return id The id of the newly created campaign (1-based).
    function createCampaign(uint256 _goal, uint256 _durationSeconds) external returns (uint256 id) {
        require(_goal > 0, "Goal must be > 0");
        require(_durationSeconds > 0, "Duration must be > 0");

        campaignCount += 1;
        id = campaignCount;

        campaigns[id] = Campaign({
            creator: payable(msg.sender),
            goal: _goal,
            pledged: 0,
            deadline: block.timestamp + _durationSeconds,
            withdrawn: false
        });

        emit CampaignCreated(id, msg.sender, _goal, campaigns[id].deadline);
    }

    /// @notice Contribute to a campaign. Send ETH with this call.
    /// @param _id Campaign ID.
    function contribute(uint256 _id) external payable campaignExists(_id) {
        Campaign storage c = campaigns[_id];
        require(block.timestamp <= c.deadline, "Campaign expired");
        require(msg.value > 0, "Must send ETH to contribute");
        require(!c.withdrawn, "Campaign funds already withdrawn");

        c.pledged += msg.value;
        contributions[_id][msg.sender] += msg.value;

        emit ContributionMade(_id, msg.sender, msg.value);
    }

    /// @notice Creator withdraws the funds if the goal has been met. Can be called any time after goal reached (before or after deadline).
    /// @param _id Campaign ID.
    function withdrawAsCreator(uint256 _id) external nonReentrant campaignExists(_id) {
        Campaign storage c = campaigns[_id];
        require(msg.sender == c.creator, "Only creator");
        require(!c.withdrawn, "Already withdrawn");
        require(c.pledged >= c.goal, "Goal not reached");

        c.withdrawn = true; // mark before transfer to prevent reentrancy
        uint256 amount = c.pledged;

        (bool sent, ) = c.creator.call{value: amount}("");
        require(sent, "Transfer failed");

        emit CreatorWithdrawn(_id, c.creator, amount);
    }

    /// @notice Backer claims refund if campaign failed (deadline passed and pledged < goal).
    /// @param _id Campaign ID.
    function claimRefund(uint256 _id) external nonReentrant campaignExists(_id) {
        Campaign storage c = campaigns[_id];
        require(block.timestamp > c.deadline, "Campaign still active");
        require(c.pledged < c.goal, "Campaign succeeded; no refunds");
        uint256 backed = contributions[_id][msg.sender];
        require(backed > 0, "No contribution to refund");

        // zero the contribution first (pull pattern)
        contributions[_id][msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: backed}("");
        require(sent, "Refund transfer failed");

        emit RefundClaimed(_id, msg.sender, backed);
    }

    /* ========== VIEW HELPERS ========== */

    /// @notice Get contribution amount of a backer to a campaign.
    function getContribution(uint256 _id, address _backer) external view campaignExists(_id) returns (uint256) {
        return contributions[_id][_backer];
    }

    /// @notice Get public campaign info (creator, goal, pledged, deadline, withdrawn).
    function getCampaign(uint256 _id) external view campaignExists(_id) returns (
        address creator,
        uint256 goal,
        uint256 pledged,
        uint256 deadline,
        bool withdrawn
    ) {
        Campaign storage c = campaigns[_id];
        return (c.creator, c.goal, c.pledged, c.deadline, c.withdrawn);
    }

    /// @notice Check whether a campaign is successful (pledged >= goal).
    function isSuccessful(uint256 _id) external view campaignExists(_id) returns (bool) {
        return campaigns[_id].pledged >= campaigns[_id].goal;
    }

    /* ========== FALLBACKS ========== */

    receive() external payable {
        // do nothing; contributions must be made via contribute() for correct accounting
    }

    fallback() external payable {
        // no-op
    }
}
