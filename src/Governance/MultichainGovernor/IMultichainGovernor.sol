pragma solidity 0.8.19;

/// @notice pauseable by the guardian
///
interface IMultichainGovernor {
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// --------------- Data Structures -------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// @notice Possible states that a proposal may be in
    /// TODO remove unused states per specification
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The timestamp at which voting begins: holders must delegate their votes prior to this time
        uint256 startTimestamp;
        /// @notice The timestamp at which voting ends: votes must be cast prior to this time
        uint256 endTimestamp;
        /// @notice The block at which voting began: holders must have delegated their votes prior to this block
        uint256 startBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes in abstention to this proposal
        uint256 abstainVotes;
        /// @notice The total votes on a proposal.
        uint256 totalVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice The value of the vote.
        uint8 voteValue;
        /// @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    //// ------------- View Functions ----------------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// whether or not the calldata is whitelisted for break glass guardian
    /// functions to whitelist are:
    /// - transferOwnership to rollback address
    /// - setPendingAdmin to rollback address
    /// - setAdmin to rollback address
    /// - publishMessage that adds rollback address as trusted sender in TemporalGovernor, with calldata for each chain
    /// TODO triple check that non of the aforementioned functions have hash collisions with something that would make them dangerous
    function whitelistedCalldatas(bytes calldata) external view returns (bool);

    function pauseDuration() external view returns (uint256);

    /// address the contract can be rolled back to by break glass guardian
    function governanceRollbackAddress() external view returns (address);

    /// break glass guardian
    function breakGlassGuardian() external view returns (address);

    /// pause guardian address
    function pauseGuardian() external view returns (address);

    /// @notice The total number of proposals
    function state(uint256 proposalId) external view returns (ProposalState);

    /// @notice The total amount of live proposals
    /// proposals that failed will not be included in this list
    /// HMMMM, is a proposal that is succeeded, and past the cross chain vote collection stage but not executed live?
    function liveProposals() external view returns (uint256[] memory);

    /// @dev Returns the proposal threshold (minimum number of votes to propose)
    /// changeable through governance proposals
    function proposalThreshold() external view returns (uint256);

    /// @dev Returns the voting period for a proposal to pass
    function votingPeriod() external view returns (uint256);

    /// @dev Returns the voting delay before voting begins
    function votingDelay() external view returns (uint256);

    /// @dev Returns the cross chain voting period for a given proposal
    function crossChainVoteCollectionPeriod() external view returns (uint256);

    /// @dev Returns the quorum for a proposal to pass
    function quorum() external view returns (uint256);

    /// @notice for backwards compatability with OZ governor
    function quorum(uint256) external view returns (uint256);

    /// @dev Returns the maximum number of live proposals per user
    /// changeable through governance proposals
    function maxUserLiveProposals() external view returns (uint256);

    /// @dev Returns the number of live proposals for a given user
    function currentUserLiveProposals(
        address user
    ) external view returns (uint256);

    /// @dev Returns the number of votes for a given user
    /// queries WELL, xWELL, distributor, and safety module
    function getVotingPower(
        address voter,
        uint256 blockNumber
    ) external view returns (uint256);

    /// @dev Returns the proposal ID for the proposed proposal
    /// only callable if user has proposal threshold or more votes
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    function execute(uint256 proposalId) external;

    /// @dev callable only by the proposer, cancels proposal if it has not been executed
    function proposerCancel(uint256 proposalId) external;

    /// @dev callable by anyone, succeeds in cancellation if user has less votes than proposal threshold
    /// at the current point in time.
    /// reverts otherwise.
    function permissionlessCancel(uint256 proposalId) external;

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////
    /// ---------- governance only functions ---------- ////
    //// ---------------------------------------------- ////
    //// ---------------------------------------------- ////

    /// updates the proposal threshold
    function updateProposalThreshold(uint256 newProposalThreshold) external;

    /// updates the maximum user live proposals
    function updateMaxUserLiveProposals(uint256 newMaxLiveProposals) external;

    /// updates the quorum
    function updateQuorum(uint256 newQuorum) external;

    /// updates the voting period
    function updateVotingPeriod(uint256 newVotingPeriod) external;

    /// updates the voting delay
    function updateVotingDelay(uint256 newVotingDelay) external;

    /// updates the cross chain voting collection period
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external;

    function setBreakGlassGuardian(address newGuardian) external;

    function setGovernanceReturnAddress(address newAddress) external;

    //// @notice array lengths must add up
    /// values must sum to msg.value to ensure guardian cannot steal funds
    /// calldata must be whitelisted
    /// only break glass guardian can call, once, and when they do, their role is revoked
    function executeBreakGlass(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable;
}
