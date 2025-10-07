#SimpleDAO.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleDAO {
    struct Proposal {
        string description;
        uint voteCount;
        bool executed;
    }

    mapping(address => bool) public members;
    Proposal[] public proposals;

    constructor() {
        members[msg.sender] = true; // creator is first member
    }

    modifier onlyMember() {
        require(members[msg.sender], "Not a DAO member");
        _;
    }

    function addMember(address _newMember) external onlyMember {
        members[_newMember] = true;
    }

    function createProposal(string memory _description) external onlyMember {
        proposals.push(Proposal(_description, 0, false));
    }

    function vote(uint _proposalId) external onlyMember {
        Proposal storage proposal = proposals[_proposalId];
        proposal.voteCount++;
    }

    function executeProposal(uint _proposalId) external onlyMember {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.executed, "Already executed");
        require(proposal.voteCount > 1, "Not enough votes");
        proposal.executed = true;
    }

    function getProposalsCount() external view returns (uint) {
        return proposals.length;
    }
}
