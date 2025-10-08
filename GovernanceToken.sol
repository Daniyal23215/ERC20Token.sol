#GovernanceToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Advanced Governance Example (no imports)
/// @notice ERC20 with permit + delegation + a Governor with simple timelock
/// @dev Educational example — not audited for production use

contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), owner); }
    modifier onlyOwner() { require(msg.sender == owner, "Ownable: caller is not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status;
    constructor() { _status = 1; }
    modifier nonReentrant() {
        require(_status == 1, "ReentrancyGuard: reentrant");
        _status = 2;
        _;
        _status = 1;
    }
}

/// @notice Minimal utils for ECDSA recover
library ECDSA {
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // signature: r(32) + s(32) + v(1) or r+s+v as 65 bytes
        require(signature.length == 65, "ECDSA: invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "ECDSA: invalid v");
        return ecrecover(hash, v, r, s);
    }
}

/// @notice ERC-20 with permit (EIP-2612) and delegation checkpoints
contract GovToken is Ownable {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // EIP-2612
    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x8fcbaf0c2ffb0e6f4edb86fc5a77b6b2d65fe0a02cf99f3b0e93f1f4f8b4a8f3;

    // Delegation (Compound style)
    mapping(address => address) public delegates;
    struct Checkpoint { uint32 fromBlock; uint256 votes; }
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;
    mapping(address => uint32) public numCheckpoints;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    constructor(string memory _name, string memory _symbol, uint256 initialSupply) {
        name = _name;
        symbol = _symbol;

        // mint to owner
        _mint(msg.sender, initialSupply);

        // Build EIP-712 domain separator
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // --- ERC20 basic functions ---
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ERC20: allowance");
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "ERC20: to zero");
        uint256 fromBal = balanceOf[from];
        require(fromBal >= value, "ERC20: balance");
        balanceOf[from] = fromBal - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        _moveDelegates(delegates[from], delegates[to], value);
    }

    // mint (owner only)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to zero");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
        _moveDelegates(address(0), delegates[to], amount);
    }

    // --- EIP-2612 permit ---
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(block.timestamp <= deadline, "Permit: expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender, value, nonces[owner_]++, deadline));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ECDSA.recover(hash, signature);
        require(signer == owner_, "Permit: invalid signature");
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    // --- Delegation ---
    function delegate(address delegatee) external {
        _delegate(msg.sender, delegatee);
    }

    function _delegate(address delegator, address delegatee) internal {
        address current = delegates[delegator];
        delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, current, delegatee);

        uint256 delegatorBalance = balanceOf[delegator];
        _moveDelegates(current, delegatee, delegatorBalance);
    }

    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 n = numCheckpoints[account];
        return n > 0 ? checkpoints[account][n - 1].votes : 0;
    }

    function getPriorVotes(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "getPriorVotes: not yet determined");
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) return 0;
        // First check most recent
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }
        // Binary search
        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) return cp.votes;
            else if (cp.fromBlock < blockNumber) lower = center;
            else upper = center - 1;
        }
        return checkpoints[account][lower].votes;
    }

    function _moveDelegates(address src, address dst, uint256 amount) internal {
        if (src == dst || amount == 0) return;
        if (src != address(0)) {
            uint32 srcNum = numCheckpoints[src];
            uint256 srcOld = srcNum > 0 ? checkpoints[src][srcNum - 1].votes : 0;
            uint256 srcNew = srcOld - amount;
            _writeCheckpoint(src, srcNum, srcOld, srcNew);
        }
        if (dst != address(0)) {
            uint32 dstNum = numCheckpoints[dst];
            uint256 dstOld = dstNum > 0 ? checkpoints[dst][dstNum - 1].votes : 0;
            uint256 dstNew = dstOld + amount;
            _writeCheckpoint(dst, dstNum, dstOld, dstNew);
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint32 blockNumber = safe32(block.number, "block number exceeds 32 bits");
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errMsg) internal pure returns (uint32) {
        require(n < 2**32, errMsg);
        return uint32(n);
    }
}

/// @notice Basic Governor contract that uses GovToken for voting power
contract Governor is ReentrancyGuard {
    GovToken public token;
    uint256 public votingDelay;      // blocks before voting starts
    uint256 public votingPeriod;     // duration in blocks
    uint256 public proposalCount;
    uint256 public proposalThreshold; // minimum votes to propose
    uint256 public quorumVotes;       // votes required for quorum

    // Timelock parameters
    uint256 public minDelay; // seconds
    mapping(bytes32 => uint256) public timelock;

    enum ProposalState { Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed }

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool canceled;
        bool executed;
        string description;
    }

    mapping(uint256 => Proposal) public proposals;

    // record who has voted on a proposal, and their support (0 = against, 1 = for)
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(address indexed voter, uint256 proposalId, bool support, uint256 weight);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);
    event ProposalCanceled(uint256 id);

    constructor(
        address tokenAddress,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumVotes,
        uint256 _minDelaySeconds
    ) {
        token = GovToken(tokenAddress);
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        proposalThreshold = _proposalThreshold;
        quorumVotes = _quorumVotes;
        minDelay = _minDelaySeconds;
    }

    // Propose: requires proposer to hold proposalThreshold votes currently
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        require(targets.length > 0, "Governor: empty proposal");
        require(targets.length == values.length && targets.length == calldatas.length, "Governor: length mismatch");
        uint256 proposerVotes = token.getCurrentVotes(msg.sender);
        require(proposerVotes >= proposalThreshold, "Governor: proposer votes below threshold");

        proposalCount++;
        uint256 id = proposalCount;

        uint256 start = block.number + votingDelay;
        uint256 end = start + votingPeriod;

        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = msg.sender;
        p.targets = targets;
        p.values = values;
        p.calldatas = calldatas;
        p.startBlock = start;
        p.endBlock = end;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.canceled = false;
        p.executed = false;
        p.description = description;

        emit ProposalCreated(id, msg.sender, targets, values, calldatas, start, end, description);
        return id;
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "Governor: unknown proposal");
        if (p.canceled) return ProposalState.Canceled;
        if (block.number <= p.startBlock) return ProposalState.Pending;
        if (block.number <= p.endBlock) return ProposalState.Active;
        if (p.forVotes + p.againstVotes < quorumVotes) return ProposalState.Defeated;
        if (p.forVotes <= p.againstVotes) return ProposalState.Defeated;
        if (!p.executed) {
            // check if queued
            bytes32 txHash = _proposalEtaHash(proposalId);
            if (timelock[txHash] != 0) return ProposalState.Queued;
            return ProposalState.Succeeded;
        }
        return ProposalState.Executed;
    }

    // Vote casting (only once per address)
    function castVote(uint256 proposalId, bool support) external {
        _castVote(msg.sender, proposalId, support);
    }

    function _castVote(address voter, uint256 proposalId, bool support) internal {
        Proposal storage p = proposals[proposalId];
        require(block.number > p.startBlock && block.number <= p.endBlock, "Governor: not active");
        require(!hasVoted[proposalId][voter], "Governor: already voted");

        uint256 weight = token.getPriorVotes(voter, p.startBlock);
        require(weight > 0, "Governor: no voting weight");

        hasVoted[proposalId][voter] = true;
        if (support) p.forVotes += weight;
        else p.againstVotes += weight;

        emit VoteCast(voter, proposalId, support, weight);
    }

    // Queue succeeded proposal into timelock
    function queue(uint256 proposalId, uint256 delaySeconds) external {
        Proposal storage p = proposals[proposalId];
        require(!p.canceled, "Governor: canceled");
        require(state(proposalId) == ProposalState.Succeeded, "Governor: not succeeded");
        require(delaySeconds >= minDelay, "Governor: delay less than min");

        // compute ETA and store
        uint256 eta = block.timestamp + delaySeconds;
        bytes32 h = _proposalEtaHash(proposalId);
        timelock[h] = eta;

        emit ProposalQueued(proposalId, eta);
    }

    // Execute queued proposal
    function execute(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(!p.canceled, "Governor: canceled");
        bytes32 h = _proposalEtaHash(proposalId);
        uint256 eta = timelock[h];
        require(eta != 0 && block.timestamp >= eta, "Governor: not ready");
        require(state(proposalId) == ProposalState.Queued || state(proposalId) == ProposalState.Succeeded, "Governor: wrong state");

        // clear timelock
        delete timelock[h];

        p.executed = true;
        // execute all actions
        for (uint i = 0; i < p.targets.length; i++) {
            (bool ok, bytes memory res) = p.targets[i].call{ value: p.values[i] }(p.calldatas[i]);
            require(ok, _getRevertMsg(res));
        }

        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(msg.sender == p.proposer, "Governor: only proposer"); // simple policy
        require(!p.executed, "Governor: executed");
        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    // compute hash for timelock identification
    function _proposalEtaHash(uint256 proposalId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("GOV_PROPOSAL", proposalId));
    }

    // If call failed, try to get revert reason
    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        if (_returnData.length < 68) return "Governor: call reverted";
        assembly {
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string));
    }

    // Helper to receive ETH (if proposals send ETH)
    receive() external payable {}
}

