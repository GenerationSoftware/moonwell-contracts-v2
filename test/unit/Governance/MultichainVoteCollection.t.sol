pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";

import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";

contract MultichainVoteCollectionUnitTest is MultichainBaseTest {
    event CrossChainVoteCollected(
        uint256 proposalId,
        uint16 sourceChain,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    function testSetup() public {
        assertEq(
            governor.getVotes(
                address(this),
                block.timestamp - 1,
                block.number - 1
            ),
            14_000_000_000 * 1e18,
            "incorrect vote amount"
        );
        assertEq(
            governor.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            voteCollection.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            voteCollection.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        assertEq(
            address(voteCollection.xWell()),
            address(xwell),
            "xwell incorrect"
        );
        assertEq(
            address(voteCollection.stkWell()),
            address(stkWellBase),
            "stkwell incorrect"
        );

        assertEq(
            address(governor.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole relayer"
        );
        assertTrue(
            voteCollection.isTrustedSender(
                moonBeamWormholeChainId,
                address(governor)
            ),
            "governor not whitelisted to send messages in"
        );
        assertTrue(
            governor.isTrustedSender(
                baseWormholeChainId,
                address(voteCollection)
            ),
            "voteCollection not whitelisted to send messages in"
        );

        assertTrue(governor.bridgeCostAll() != 0, "no targets");

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains length"
        );

        assertEq(voteCollection.owner(), address(this), "incorrect owner");
    }

    /// Proposing on MultichainGovernor

    function testProposeUpdateProposalThresholdSucceeds()
        public
        returns (uint256)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startProposalCount = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        uint256 endProposalCount = governor.proposalCount();

        assertEq(
            startProposalCount + 1,
            endProposalCount,
            "proposal count incorrect"
        );
        assertEq(proposalId, endProposalCount, "proposal id incorrect");
        assertTrue(governor.proposalActive(proposalId), "proposal not active");

        {
            IMultichainGovernor.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                    proposalId
                );

            IMultichainGovernor.ProposalInformation
                memory governorInfo = governor.proposalInformationStruct(
                    proposalId
                );

            assertEq(
                voteCollectionInfo.voteSnapshotTimestamp,
                governorInfo.voteSnapshotTimestamp,
                "incorrect snapshot start timestamp"
            );
            assertEq(
                voteCollectionInfo.votingStartTime,
                governorInfo.votingStartTime,
                "incorrect voting start time"
            );
            assertEq(
                voteCollectionInfo.votingEndTime,
                governorInfo.votingEndTime,
                "incorrect end timestamp"
            );
            assertEq(
                voteCollectionInfo.crossChainVoteCollectionEndTimestamp,
                governorInfo.crossChainVoteCollectionEndTimestamp,
                "incorrect cross chain vote collection end timestamp"
            );
        }

        uint256[] memory proposals = governor.liveProposals();

        bool proposalFound;

        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i] == proposalId) {
                proposalFound = true;
                break;
            }
        }

        assertTrue(proposalFound, "proposal not found in live proposals");

        _assertGovernanceBalance();

        return proposalId;
    }

    /// Voting on MultichainVoteCollection

    function testVotingValidProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal vote snapshot timestamp from proposal information
        (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // get user vote power
        uint256 votePower = voteCollection.getVotes(
            address(this),
            voteSnapshotTimestamp
        );

        // get proposal votes before voting
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        (bool hasVoted, uint256 voteValue, uint256 voteAmount) = voteCollection
            .getReceipt(proposalId, address(this));
        assertTrue(hasVoted, "user did not vote");
        assertEq(voteValue, Constants.VOTE_VALUE_YES, "vote value incorrect");
        assertEq(voteAmount, votePower, "vote amount incorrect");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesFor, 4_000_000_000 * 1e18, "votes for incorrect");
        assertEq(votesFor - votesForBefore, voteAmount, "votes for incorrect");
        assertEq(votesAgainst, votesAgainstBefore, "votes against incorrect");
        assertEq(votesAbstain, votesAbstainBefore, "abstain votes incorrect");
        assertEq(
            totalVotes,
            totalVotesBefore + votePower,
            "total votes incorrect"
        );
        assertEq(votesFor, totalVotes, "total votes incorrect");

        _assertGovernanceBalance();
    }

    function testVotingValidProposalIdBeforeStartFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        (, uint256 votingStartTime, , , , , , ) = voteCollection
            .proposalInformation(proposalId);

        vm.warp(votingStartTime - 1);
        vm.expectRevert("MultichainVoteCollection: Voting has not started yet");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);
    }

    // voter has no votes
    function testVotingVoterHasNoVotes() public {
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );
        vm.prank(address(1));
        vm.expectRevert("MultichainVoteCollection: voter has no votes");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
    }

    /// cannot vote twice on the same proposal
    function testVotingTwiceSameProposalFails() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        vm.expectRevert("MultichainVoteCollection: voter already voted");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
    }

    function testVotingValidProposalIdInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);

        _assertGovernanceBalance();
    }

    function testVotingActiveProposalIdSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before cast
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        (bool hasVoted, uint256 voteValue, uint256 voteAmount) = voteCollection
            .getReceipt(proposalId, address(this));

        assertTrue(hasVoted, "user did not vote");
        assertEq(voteValue, Constants.VOTE_VALUE_NO, "vote value incorrect");
        assertEq(voteAmount, 4_000_000_000 * 1e18, "vote amount incorrect");

        (
            uint256 totalVotes,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = voteCollection.proposalVotes(proposalId);

        assertEq(votesAgainst, 4_000_000_000 * 1e18, "votes against incorrect");
        assertEq(
            votesAgainst - votesAgainstBefore,
            4_000_000_000 * 1e18,
            "votes against incorrect"
        );
        assertEq(votesFor, votesForBefore, "votes for incorrect");
        assertEq(votesAbstain, votesAbstainBefore, "abstain votes incorrect");
        assertEq(
            totalVotes,
            totalVotesBefore + 4_000_000_000 * 1e18,
            "total votes incorrect"
        );
        assertEq(votesAgainst, totalVotes, "total votes incorrect");

        _assertGovernanceBalance();
    }

    function testVotingPastVoteEndTimeProposalFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in crosschain vote collection period"
        );

        vm.expectRevert("MultichainVoteCollection: Voting has ended");
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

        _assertGovernanceBalance();
    }

    function testVotingInvalidVoteValueFails()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: invalid vote value");
        voteCollection.castVote(proposalId, 3);

        _assertGovernanceBalance();
    }

    function testVotingNoVotesFails() public returns (uint256 proposalId) {
        proposalId = _createProposalUpdateThreshold(address(this));

        vm.warp(block.timestamp + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        vm.expectRevert("MultichainVoteCollection: voter has no votes");
        vm.prank(address(1));
        voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

        _assertGovernanceBalance();
    }

    /// Multiple users all voting on the same proposal

    /// WELL
    function testMultipleUserVoteWellSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(user1, voteAmount);
        xwell.transfer(user2, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user1);

        vm.prank(user2);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user3);

        /// include users before snapshot block
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        uint256 snapshotTimestamp = block.timestamp - 1;
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        {
            vm.prank(user1);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesFor - votesForBefore,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst,
                votesAgainstBefore,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user1);

            assertTrue(hasVoted, "user1 has not voted");
            assertEq(votes, voteAmount, "user1 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_YES,
                "user1 did not vote yes"
            );
        }

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }

        {
            vm.prank(user3);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 3,
                "total votes incorrect"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user3);

            assertTrue(hasVoted, "user3 has not voted");
            assertEq(votes, voteAmount, "user3 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user3 did not vote yes"
            );
        }

        {
            IMultichainGovernor.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                    proposalId
                );

            assertEq(
                snapshotTimestamp,
                voteCollectionInfo.voteSnapshotTimestamp,
                "snapshot timestamp incorrect"
            );
            assertEq(
                voteCollectionInfo.voteSnapshotTimestamp + 1,
                voteCollectionInfo.votingStartTime,
                "voting start time incorrect"
            );

            assertEq(
                voteCollectionInfo.totalVotes,
                voteCollectionInfo.forVotes +
                    voteCollectionInfo.againstVotes +
                    voteCollectionInfo.abstainVotes,
                "incorrect total votes"
            );
        }

        _assertGovernanceBalance();
    }

    function testMultipleUserVoteWithXWellDelegationSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(address(user1), voteAmount);
        xwell.transfer(address(user3), voteAmount);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }

        {
            vm.prank(user4);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user4);

            assertTrue(hasVoted, "user4 has not voted");
            assertEq(votes, voteAmount, "user4 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user4 did not vote no"
            );
        }

        IMultichainGovernor.ProposalInformation
            memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                proposalId
            );

        assertEq(
            voteCollectionInfo.totalVotes,
            voteCollectionInfo.forVotes +
                voteCollectionInfo.againstVotes +
                voteCollectionInfo.abstainVotes,
            "incorrect total votes"
        );

        assertEq(
            voteCollectionInfo.totalVotes,
            2 * voteAmount,
            "incorrect total votes"
        );
        assertEq(voteCollectionInfo.forVotes, 0, "incorrect for votes");
        assertEq(
            voteCollectionInfo.againstVotes,
            voteAmount,
            "incorrect against votes"
        );
        assertEq(
            voteCollectionInfo.abstainVotes,
            voteAmount,
            "incorrect abstain votes"
        );

        _assertGovernanceBalance();
    }

    /// xWELL
    function testMultipleUserVotexWellSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        uint256 voteAmount = 1_000_000 * 1e18;

        xwell.transfer(user1, voteAmount);
        xwell.transfer(user2, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user1);

        vm.prank(user2);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user3);

        /// include users before snapshot timestamp
        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get proposal votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user1);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_YES);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesFor - votesForBefore,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst,
                votesAgainstBefore,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes incorrect"
            );
        }

        {
            vm.prank(user3);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, voteAmount, "votes for incorrect");
            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 3,
                "total votes incorrect"
            );
        }

        {
            IMultichainGovernor.ProposalInformation
                memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                    proposalId
                );

            assertEq(
                voteCollectionInfo.totalVotes,
                voteCollectionInfo.forVotes +
                    voteCollectionInfo.againstVotes +
                    voteCollectionInfo.abstainVotes,
                "incorrect total votes"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user1);

            assertTrue(hasVoted, "user1 has not voted");
            assertEq(votes, voteAmount, "user1 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_YES,
                "user1 did not vote yes"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }
        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user3);

            assertTrue(hasVoted, "user3 has not voted");
            assertEq(votes, voteAmount, "user3 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_ABSTAIN,
                "user3 did not vote yes"
            );
        }

        IMultichainGovernor.ProposalInformation
            memory governorInfo = _getVoteCollectionProposalInformation(
                proposalId
            );

        assertEq(
            governorInfo.totalVotes,
            governorInfo.forVotes +
                governorInfo.againstVotes +
                governorInfo.abstainVotes,
            "incorrect total votes"
        );

        assertEq(
            governorInfo.totalVotes,
            3 * voteAmount,
            "incorrect total votes"
        );
        assertEq(governorInfo.forVotes, voteAmount, "incorrect for votes");
        assertEq(
            governorInfo.againstVotes,
            voteAmount,
            "incorrect against votes"
        );
        assertEq(
            governorInfo.abstainVotes,
            voteAmount,
            "incorrect abstain votes"
        );

        _assertGovernanceBalance();
    }

    function testMultipleUserVoteWithxWellDelegationSucceeds() public {
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(3);
        address user4 = address(4);

        uint256 voteAmount = 1_000_000 * 1e18;
        xwell.transfer(user1, voteAmount);
        xwell.transfer(user3, voteAmount);

        vm.prank(user1);
        xwell.delegate(user2);

        vm.prank(user3);
        xwell.delegate(user4);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect state, not active"
        );

        // get votes before
        (
            uint256 totalVotesBefore,
            uint256 votesForBefore,
            uint256 votesAgainstBefore,
            uint256 votesAbstainBefore
        ) = voteCollection.proposalVotes(proposalId);

        {
            vm.prank(user2);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = voteCollection
                .getReceipt(proposalId, user2);

            assertTrue(hasVoted, "user2 has not voted");
            assertEq(votes, voteAmount, "user2 has incorrect vote amount");
            assertEq(
                voteValue,
                Constants.VOTE_VALUE_NO,
                "user2 did not vote no"
            );
        }

        {
            vm.prank(user4);
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_ABSTAIN);

            // check proposal votes after
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
            assertEq(
                votesAbstain - votesAbstainBefore,
                voteAmount,
                "abstain votes incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount * 2,
                "total votes"
            );
        }

        _assertGovernanceBalance();
    }

    // Emit votes to Governor
    function testEmitVotesToGovernorSucceeded()
        public
        returns (uint256 proposalId)
    {
        testMultipleUserVoteWellSucceeds();

        proposalId = governor.proposalCount();

        IMultichainGovernor.ProposalInformation
            memory proposalVoteCollection = _getVoteCollectionProposalInformation(
                proposalId
            );

        // test at the last timestamp of the cross chain vote collection period
        vm.warp(proposalVoteCollection.crossChainVoteCollectionEndTimestamp);

        assertEq(
            uint256(governor.state(proposalId)),
            1,
            "incorrect state, not in crosschain vote collection period"
        );

        IMultichainGovernor.ProposalInformation memory proposalBefore = governor
            .proposalInformationStruct(proposalId);

        {
            uint256 bridgeCost = voteCollection.bridgeCost(
                moonBeamWormholeChainId
            );

            vm.deal(address(this), bridgeCost);

            voteCollection.emitVotes{value: bridgeCost}(proposalId);
        }

        IMultichainGovernor.ProposalInformation memory proposalAfter = governor
            .proposalInformationStruct(proposalId);

        assertEq(
            proposalAfter.totalVotes,
            proposalBefore.totalVotes + proposalVoteCollection.totalVotes,
            "incorrect total votes"
        );
        assertEq(
            proposalAfter.forVotes,
            proposalBefore.forVotes + proposalVoteCollection.forVotes,
            "incorrect for votes"
        );
        assertEq(
            proposalAfter.againstVotes,
            proposalBefore.againstVotes + proposalVoteCollection.againstVotes,
            "incorrect against votes"
        );
        assertEq(
            proposalAfter.abstainVotes,
            proposalBefore.abstainVotes + proposalVoteCollection.abstainVotes,
            "incorrect abstain votes"
        );

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalHasNoVotes() public {
        _createProposalUpdateThreshold(address(this));

        uint256 proposalId = governor.proposalCount();

        vm.expectRevert("MultichainVoteCollection: proposal has no votes");
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalEndTimeHasNotPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp);

        vm.expectRevert("MultichainVoteCollection: Voting has not ended");
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalEndTimeHasPassedBridgeOutIncorrectAmount()
        public
    {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        (, , uint256 endTimestamp, , , , , ) = voteCollection
            .proposalInformation(proposalId);

        // test at the last timestamp of vote period
        vm.warp(endTimestamp + 1);

        uint256 cost = voteCollection.bridgeCost(moonBeamWormholeChainId) - 1;
        vm.deal(address(this), cost);

        vm.expectRevert("WormholeBridge: total cost not equal to quote");
        voteCollection.emitVotes{value: cost}(proposalId);

        _assertGovernanceBalance();
    }

    function testEmitVotesProposalCollectionEndTimeHasPassed() public {
        uint256 proposalId = testVotingValidProposalIdSucceeds();

        IMultichainGovernor.ProposalInformation
            memory voteCollectionInfo = _getVoteCollectionProposalInformation(
                proposalId
            );

        vm.warp(voteCollectionInfo.crossChainVoteCollectionEndTimestamp + 1);

        vm.expectRevert(
            "MultichainVoteCollection: Voting collection phase has ended"
        );
        voteCollection.emitVotes(proposalId);

        _assertGovernanceBalance();
    }

    /// Only Owner

    function testSetGasLimitOwnerSucceeds() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        voteCollection.setGasLimit(gasLimit);
        assertEq(voteCollection.gasLimit(), gasLimit, "incorrect gas limit");
    }

    function testSetGasLimitTooLow() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT - 1;
        vm.expectRevert("MultichainVoteCollection: gas limit too low");
        voteCollection.setGasLimit(gasLimit);
    }

    function testSetGasLimitNonOwnerFails() public {
        uint96 gasLimit = Constants.MIN_GAS_LIMIT;
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        voteCollection.setGasLimit(gasLimit);
    }

    // VIEW FUNCTIONS

    function testGetChainAddresVotes() public {
        uint256 proposalId = testEmitVotesToGovernorSucceeded();

        uint256 voteAmount = 1_000_000 * 1e18;

        (
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votesAbstain
        ) = governor.chainAddressVotes(proposalId, 30); // base chain id

        assertEq(votesFor, voteAmount, "votes for incorrect");
        assertEq(votesAgainst, voteAmount, "votes against incorrect");
        assertEq(votesAbstain, voteAmount, "abstain votes incorrect");
    }

    // bridge in

    function testBridgeInWrongSourceChain() public {
        bytes memory payload = abi.encode(0, 0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("WormholeBridge: sender not trusted");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonBeamWormholeChainId, // pass moonbeam as the target chain so that relayer adapter do the flip
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInWrongPayloadLength() public {
        bytes memory payload = abi.encode(0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("MultichainVoteCollection: invalid payload length");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            baseWormholeChainId,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInProposalAlreadyExist() public {
        uint256 proposalId = _createProposalUpdateThreshold(address(this));

        bytes memory payload = abi.encode(proposalId, 0, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert("MultichainVoteCollection: proposal already exists");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            baseWormholeChainId,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingSnapshotTimeGreaterThanStartTime() public {
        vm.warp(1);

        bytes memory payload = abi.encode(0, 4, 3, 3, 4);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: snapshot time must be before start time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingSnapshotTimeEqStartTime() public {
        vm.warp(1);

        bytes memory payload = abi.encode(0, 4, 4, 3, 4);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: snapshot time must be before start time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingStartTimeGreaterThanVoteEndTime() public {
        vm.warp(1);
        bytes memory payload = abi.encode(0, 2, 3, 2, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: start time must be before end time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVoteCollectionEndLtThanVoteEndTime() public {
        vm.warp(1);
        bytes memory payload = abi.encode(0, 2, 3, 4, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: end time must be before vote collection end"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingStartTimeEqVoteEndTime() public {
        vm.warp(1);
        bytes memory payload = abi.encode(0, 1, 2, 2, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: start time must be before end time"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    function testBridgeInVotingEndTimeLessThanTimestamp() public {
        bytes memory payload = abi.encode(0, 0, 1, 2, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(governor), gasCost);
        vm.prank(address(governor));
        vm.expectRevert(
            "MultichainVoteCollection: end time must be in the future"
        );
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            30,
            address(voteCollection),
            payload,
            0,
            0
        );
    }

    // test governor bridge in votes already collected here to reuse emit votes test
    function testBridgeInVotesAlreadyCollected() public {
        uint256 proposalId = testEmitVotesToGovernorSucceeded();

        bytes memory payload = abi.encode(proposalId, 0, 0, 0);
        uint256 gasCost = wormholeRelayerAdapter.nativePriceQuote();

        vm.deal(address(voteCollection), gasCost);
        vm.prank(address(voteCollection));
        vm.expectRevert("MultichainGovernor: vote already collected");
        wormholeRelayerAdapter.sendPayloadToEvm{value: gasCost}(
            moonBeamWormholeChainId,
            address(governor),
            payload,
            0,
            0
        );
    }

    // multiple collections

    function testEmitToMultipleVoteCollections()
        public
        returns (address proxyVoteCollection2)
    {
        (proxyVoteCollection2, ) = deployVoteCollection(
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            moonBeamWormholeChainId,
            proxyAdmin,
            address(this)
        );
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        uint16 chainId = 2;
        _trustedSenders[0].chainId = chainId;
        _trustedSenders[0].addr = address(proxyVoteCollection2);

        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            baseWormholeChainId,
            bridgeCost / 2,
            address(voteCollection),
            payload
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            chainId,
            bridgeCost / 2,
            proxyVoteCollection2,
            payload
        );

        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        {
            // vote collections should have the proposal
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
                .proposalInformation(1);
            assertGt(voteSnapshotTimestamp, 0, "proposal id incorrect");
        }

        {
            MultichainVoteCollection voteCollection2 = MultichainVoteCollection(
                proxyVoteCollection2
            );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection2
                .proposalInformation(1);

            assertGt(voteSnapshotTimestamp, 1, "proposal id incorrect");
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
    }

    function testEmitToMultipleVoteCollectionsSomeFails() public {
        (address proxyVoteCollection2, ) = deployVoteCollection(
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            moonBeamWormholeChainId,
            proxyAdmin,
            address(this)
        );

        (address proxyVoteCollection3, ) = deployVoteCollection(
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            moonBeamWormholeChainId,
            proxyAdmin,
            address(this)
        );

        (address proxyVoteCollection4, ) = deployVoteCollection(
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            moonBeamWormholeChainId,
            proxyAdmin,
            address(this)
        );

        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                3
            );

        _trustedSenders[0].chainId = 2;
        _trustedSenders[0].addr = address(proxyVoteCollection2);

        _trustedSenders[1].chainId = 3;
        _trustedSenders[1].addr = address(proxyVoteCollection3);

        _trustedSenders[2].chainId = 4;
        _trustedSenders[2].addr = address(proxyVoteCollection4);

        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        wormholeRelayerAdapter.setShouldRevertChain(2, true);
        wormholeRelayerAdapter.setShouldRevertChain(4, true);

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            baseWormholeChainId,
            bridgeCost / 4,
            address(voteCollection),
            payload
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(2, payload, bridgeCost / 4);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(3, bridgeCost / 4, proxyVoteCollection3, payload);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(4, payload, bridgeCost / 4);

        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        {
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
                .proposalInformation(1);
            assertGt(voteSnapshotTimestamp, 0, "proposal doesn't exist");
        }

        {
            MultichainVoteCollection voteCollection2 = MultichainVoteCollection(
                proxyVoteCollection2
            );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection2
                .proposalInformation(1);

            assertEq(voteSnapshotTimestamp, 0, "proposal exist");
        }

        {
            MultichainVoteCollection voteCollection3 = MultichainVoteCollection(
                proxyVoteCollection3
            );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection3
                .proposalInformation(1);

            assertGt(voteSnapshotTimestamp, 0, "proposal doesn't exist");
        }

        {
            MultichainVoteCollection voteCollection4 = MultichainVoteCollection(
                proxyVoteCollection4
            );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection4
                .proposalInformation(1);

            assertEq(voteSnapshotTimestamp, 0, "proposal exist");
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
        assertEq(proxyVoteCollection3.balance, 0, "balance should be zero");
        assertEq(proxyVoteCollection4.balance, 0, "balance should be zero");
    }

    function testCollectVotesFromMultipleVoteCollections() public {
        address proxyVoteCollection2 = testEmitToMultipleVoteCollections();
        uint256 proposalId = 1;

        MultichainVoteCollection voteCollection2 = MultichainVoteCollection(
            proxyVoteCollection2
        );
        uint256 voteAmount = 4_000_000_000 * 1e18;

        {
            // votes before

            (
                uint256 totalVotesBefore,
                uint256 votesForBefore,
                uint256 votesAgainstBefore,
                uint256 votesAbstainBefore
            ) = voteCollection.proposalVotes(proposalId);

            // cast votes for both collections
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // votes after cast
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            (
                uint256 totalVotesBefore2,
                uint256 votesForBefore2,
                uint256 votesAgainstBefore2,
                uint256 votesAbstainBefore2
            ) = voteCollection2.proposalVotes(1);

            voteCollection2.castVote(1, Constants.VOTE_VALUE_YES);

            (
                uint256 totalVotes2,
                uint256 votesFor2,
                uint256 votesAgainst2,
                uint256 votesAbstain2
            ) = voteCollection2.proposalVotes(1);

            assertEq(votesFor2, voteAmount, "votes for incorrect");
            assertEq(
                votesFor2 - votesForBefore2,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst2,
                votesAgainstBefore2,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain2,
                votesAbstainBefore2,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes2,
                totalVotesBefore2 + voteAmount,
                "total votes incorrect"
            );
        }

        // pass to cross chain vote collection period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        {
            // total votes on governor
            (
                uint256 totalVotesBefore,
                uint256 votesForBefore,
                uint256 votesAgainstBefore,
                uint256 votesAbstainBefore
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotesBefore, 0, "total votes incorrect");
            assertEq(votesForBefore, 0, "votes for incorrect");
            assertEq(votesAgainstBefore, 0, "votes against incorrect");
            assertEq(votesAbstainBefore, 0, "abstain votes incorrect");

            {
                uint256 bridgeCost = voteCollection.bridgeCost(
                    moonBeamWormholeChainId
                );

                vm.deal(address(this), bridgeCost);

                vm.expectEmit(true, true, true, true, address(governor));
                emit CrossChainVoteCollected(
                    proposalId,
                    baseWormholeChainId,
                    0,
                    voteAmount,
                    0
                );

                voteCollection.emitVotes{value: bridgeCost}(proposalId);

                {
                    // check chainVoteCollectorVotes
                    (
                        uint256 forVotes,
                        uint256 againstVotes,
                        uint256 abstainVotes
                    ) = governor.chainVoteCollectorVotes(
                            baseWormholeChainId,
                            proposalId
                        );

                    assertEq(againstVotes, voteAmount, "chain votes incorrect");
                    assertEq(forVotes, 0, "chain votes incorrect");
                    assertEq(abstainVotes, 0, "chain votes incorrect");
                }

                // check proposal votes after
                (
                    uint256 totalVotes,
                    uint256 votesFor,
                    uint256 votesAgainst,
                    uint256 votesAbstain
                ) = governor.proposalVotes(proposalId);

                assertEq(
                    votesAgainst,
                    voteAmount,
                    "governor votes against incorrect"
                );
                assertEq(
                    votesFor,
                    votesForBefore,
                    "governor votes for incorrect"
                );
                assertEq(
                    votesAbstain,
                    votesAbstainBefore,
                    "governor abstain votes incorrect"
                );
                assertEq(
                    totalVotes,
                    totalVotesBefore + votesAgainst,
                    "governor total votes incorrect"
                );
            }

            {
                uint256 bridgeCost = voteCollection2.bridgeCost(
                    moonBeamWormholeChainId
                );

                vm.deal(address(this), bridgeCost);

                wormholeRelayerAdapter.setSenderChainId(2);
                vm.expectEmit(true, true, true, true, address(governor));
                emit CrossChainVoteCollected(proposalId, 2, voteAmount, 0, 0);

                voteCollection2.emitVotes{value: bridgeCost}(proposalId);

                {
                    // check chainVoteCollectorVotes
                    (
                        uint256 forVotes,
                        uint256 againstVotes,
                        uint256 abstainVotes
                    ) = governor.chainVoteCollectorVotes(2, proposalId);

                    assertEq(againstVotes, 0, "chain votes incorrect");
                    assertEq(forVotes, voteAmount, "chain votes incorrect");
                    assertEq(abstainVotes, 0, "chain votes incorrect");
                }

                // check proposal votes after
                (
                    uint256 totalVotes,
                    uint256 votesFor,
                    uint256 votesAgainst,
                    uint256 votesAbstain
                ) = governor.proposalVotes(1);

                assertEq(
                    votesFor,
                    votesForBefore + voteAmount,
                    "votes for incorrect"
                );
                assertEq(
                    votesAgainst,
                    votesAgainstBefore + voteAmount,
                    "votes against incorrect"
                );
                assertEq(
                    votesAbstain,
                    votesAbstainBefore,
                    "abstain votes incorrect"
                );
                assertEq(
                    totalVotes,
                    totalVotesBefore + voteAmount * 2,
                    "total votes incorrect"
                );
            }
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
    }
}
