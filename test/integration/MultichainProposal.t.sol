// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {TestMultichainProposals} from "@protocol/proposals/TestMultichainProposals.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {ITemporalGovernor, TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

import {mipm18a} from "@proposals/mips/mip-m18/mip-m18a.sol";
import {mipm18b} from "@proposals/mips/mip-m18/mip-m18b.sol";
import {mipm18c} from "@proposals/mips/mip-m18/mip-m18c.sol";
import {mipm18d} from "@proposals/mips/mip-m18/mip-m18d.sol";
import {mipm18e} from "@proposals/mips/mip-m18/mip-m18e.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata

/*
if the tests fail, try setting the environment variables as follows:

export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_AFTER_DEPLOY_SETUP=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true

*/
contract MultichainProposalTest is
    Test,
    ChainIds,
    CreateCode,
    TestMultichainProposals
{
    MultichainVoteCollection public voteCollection;
    MultichainGovernor public governor;
    IWormhole public wormhole;
    Timelock public timelock;
    Well public well;
    xWELL public xwell;

    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    uint256 public baseForkId = vm.createFork("https://mainnet.base.org");

    uint256 public moonbeamForkId =
        vm.createFork("https://rpc.api.moonbeam.network");

    address public constant voter = address(100_000_000);

    mipm18a public proposalA;
    mipm18b public proposalB;
    mipm18c public proposalC;
    mipm18d public proposalD;
    mipm18e public proposalE;

    TemporalGovernor public temporalGov;

    function setUp() public override {
        super.setUp();

        proposalA = new mipm18a();
        proposalB = new mipm18b();
        proposalC = new mipm18c();
        proposalD = new mipm18d();
        proposalE = new mipm18e();

        address[] memory proposalsArray = new address[](5);
        proposalsArray[0] = address(proposalA);
        proposalsArray[1] = address(proposalB);
        proposalsArray[2] = address(proposalC);
        proposalsArray[3] = address(proposalD);
        proposalsArray[4] = address(proposalE);

        proposalA.setForkIds(baseForkId, moonbeamForkId);
        proposalB.setForkIds(baseForkId, moonbeamForkId);
        proposalC.setForkIds(baseForkId, moonbeamForkId);
        proposalD.setForkIds(baseForkId, moonbeamForkId);
        proposalE.setForkIds(baseForkId, moonbeamForkId);

        /// load proposals up into the TestMultichainProposal contract
        _initialize(proposalsArray);

        vm.selectFork(moonbeamForkId);
        runProposals(false, true, true, true, true, true, true, true);

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY", baseChainId)
        );
        wormhole = IWormhole(
            addresses.getAddress("WORMHOLE_CORE", moonBeamChainId)
        );
        well = Well(addresses.getAddress("WELL", moonBeamChainId));
        timelock = Timelock(
            addresses.getAddress("MOONBEAM_TIMELOCK", moonBeamChainId)
        );
        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY", moonBeamChainId)
        );
    }

    function testSetup() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );

        assertEq(
            voteCollection.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            address(voteCollection.wormholeRelayer()),
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
            "incorrect wormhole relayer"
        );
        assertEq(
            address(voteCollection.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xWELL contract"
        );
        assertEq(
            address(voteCollection.stkWell()),
            addresses.getAddress("stkWELL_PROXY"),
            "incorrect xWELL contract"
        );

        temporalGov = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
        /// artemis timelock does not start off as trusted sender
        assertFalse(
            temporalGov.isTrustedSender(
                moonBeamWormholeChainId,
                addresses.getAddress(
                    "ARTEMIS_TIMELOCK",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "artemis timelock should not be trusted sender"
        );
        assertTrue(
            temporalGov.isTrustedSender(
                moonBeamWormholeChainId,
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "multichain governor should be trusted sender"
        );

        assertEq(
            temporalGov.allTrustedSenders(moonBeamWormholeChainId).length,
            1,
            "incorrect amount of trusted senders post proposal"
        );
    }

    function testInitializeVoteCollectionFails() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );
        /// test impl and logic contract initialization
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );
    }

    function testInitializeMultichainGovernorFails() public {
        vm.selectFork(moonbeamForkId);
        /// test impl and logic contract initialization
        MultichainGovernor.InitializeData memory initializeData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        bytes[] memory whitelistedCalldata = new bytes[](0);

        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
    }

    function testInitializeEcosystemReserveFails() public {
        vm.selectFork(baseForkId);

        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
            );

        vm.prank(ecosystemReserveController.owner());
        vm.expectRevert("ECOSYSTEM_RESERVE has been initialized");
        ecosystemReserveController.setEcosystemReserve(address(0));

        IEcosystemReserveUplift ecosystemReserve = IEcosystemReserveUplift(
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
        );

        vm.expectRevert("Initializable: contract is already initialized");
        ecosystemReserve.initialize(address(1));

        ecosystemReserve = IEcosystemReserveUplift(
            addresses.getAddress("ECOSYSTEM_RESERVE_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        ecosystemReserve.initialize(address(1));
    }

    function testRetrieveGasPriceMoonbeamSucceeds() public {
        vm.selectFork(moonbeamForkId);

        uint256 gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testRetrieveGasPriceBaseSucceeds() public {
        vm.selectFork(baseForkId);

        uint256 gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testProposeOnMoonbeamWellSucceeds() public {
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

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

        uint256 startingProposalId = governor.proposalCount();
        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        assertTrue(
            governor.userHasProposal(proposalId, address(this)),
            "user has proposal"
        );
        assertTrue(
            governor.proposalValid(proposalId),
            "user does not have proposal"
        );

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(
                governor.proposalThreshold(),
                100_000_000 * 1e18,
                "incorrect new proposal threshold"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
        }
    }

    function testVotingOnBasexWellSucceeds() public {}

    function testVotingOnBasestkWellSucceeds() public {}

    function testVotingOnBasestkWellPostVotingPeriodFails() public {}

    function testRebroadcatingVotesMultipleTimesVotePeriodMultichainGovernorSucceeds()
        public
    {
        /// propose, then rebroadcast
        vm.selectFork(moonbeamForkId);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

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

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);
        uint256 startingProposalId = governor.proposalCount();

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        assertTrue(
            governor.userHasProposal(proposalId, address(this)),
            "user has proposal"
        );
        assertTrue(
            governor.proposalValid(proposalId),
            "user does not have proposal"
        );

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        vm.deal(address(this), bridgeCost * 3);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);
        governor.rebroadcastProposal{value: bridgeCost}(proposalId);

        assertEq(address(this).balance, 0, "balance not 0 after broadcasting");
        assertEq(
            address(governor).balance,
            0,
            "balance not 0 after broadcasting"
        );
    }

    function testEmittingVotesMultipleTimesVoteCollectionPeriodSucceeds()
        public
    {}

    function testReceiveProposalFromRelayersSucceeds() public {}

    function testReceiveSameProposalFromRelayersTwiceFails() public {}

    function testEmittingVotesPostVoteCollectionPeriodFails() public {}

    /// upgrading contract logic

    function testUpgradeMultichainGovernorThroughGovProposal() public {
        vm.selectFork(moonbeamForkId);

        MockMultichainGovernor newGovernor = new MockMultichainGovernor();

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "upgrade(address,address)",
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            address(newGovernor)
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);
        uint256 startingProposalId = governor.proposalCount();

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, startingProposalId + 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        assertTrue(
            governor.userHasProposal(proposalId, address(this)),
            "user has proposal"
        );
        assertTrue(
            governor.proposalValid(proposalId),
            "user does not have proposal"
        );

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
            assertEq(
                MockMultichainGovernor(address(governor)).newFeature(),
                1,
                "incorrectly upgraded"
            );

            validateProxy(
                vm,
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                address(newGovernor),
                addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
                "moonbeam new logic contract for multichain governor"
            );
        }
    }

    /// this requires a new mock relayer contract
    function testUpgradeMultichainVoteCollection() public {}

    function testBreakGlassGuardianSucceedsSettingPendingAdminAndOwners()
        public
    {
        {
            vm.selectFork(baseForkId);
            temporalGov = TemporalGovernor(
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );
            /// artemis timelock does not start off as trusted sender
            assertFalse(
                temporalGov.isTrustedSender(
                    uint16(moonBeamWormholeChainId),
                    addresses.getAddress(
                        "ARTEMIS_TIMELOCK",
                        sendingChainIdToReceivingChainId[block.chainid]
                    )
                ),
                "artemis timelock should not be trusted sender"
            );
        }

        vm.selectFork(moonbeamForkId);
        address artemisTimelockAddress = addresses.getAddress(
            "ARTEMIS_TIMELOCK"
        );

        /// calldata to transfer system ownership back to artemis timelock
        bytes memory transferOwnershipCalldata = abi.encodeWithSignature(
            "transferOwnership(address)",
            artemisTimelockAddress
        );
        bytes memory changeAdminCalldata = abi.encodeWithSignature(
            "setAdmin(address)",
            artemisTimelockAddress
        );
        bytes memory setEmissionsManagerCalldata = abi.encodeWithSignature(
            "setEmissionsManager(address)",
            artemisTimelockAddress
        );
        bytes memory _setPendingAdminCalldata = abi.encodeWithSignature(
            "_setPendingAdmin(address)",
            artemisTimelockAddress
        );

        /// skip wormhole for now, circle back to that later and make array size 18

        /// targets
        address[] memory targets = new address[](19);
        bytes[] memory calldatas = new bytes[](19);

        targets[0] = addresses.getAddress("WORMHOLE_CORE");
        calldatas[0] = proposalC.approvedCalldata(0);

        targets[1] = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        calldatas[1] = transferOwnershipCalldata;

        targets[2] = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        calldatas[2] = transferOwnershipCalldata;

        targets[3] = addresses.getAddress("xWELL_PROXY");
        calldatas[3] = transferOwnershipCalldata;

        targets[4] = addresses.getAddress("CHAINLINK_ORACLE");
        calldatas[4] = changeAdminCalldata;

        targets[5] = addresses.getAddress("stkWELL");
        calldatas[5] = setEmissionsManagerCalldata;

        targets[6] = addresses.getAddress("UNITROLLER");
        calldatas[6] = _setPendingAdminCalldata;

        targets[7] = addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER");
        calldatas[7] = transferOwnershipCalldata;

        targets[8] = addresses.getAddress("MOONWELL_mwBTC");
        calldatas[8] = _setPendingAdminCalldata;

        targets[9] = addresses.getAddress("MOONWELL_mBUSD");
        calldatas[9] = _setPendingAdminCalldata;

        targets[10] = addresses.getAddress("MOONWELL_mETH");
        calldatas[10] = _setPendingAdminCalldata;

        targets[11] = addresses.getAddress("MOONWELL_mUSDC");
        calldatas[11] = _setPendingAdminCalldata;

        targets[12] = addresses.getAddress("mGLIMMER");
        calldatas[12] = _setPendingAdminCalldata;

        targets[13] = addresses.getAddress("mxcDOT");
        calldatas[13] = _setPendingAdminCalldata;

        targets[14] = addresses.getAddress("mxcUSDT");
        calldatas[14] = _setPendingAdminCalldata;

        targets[15] = addresses.getAddress("mFRAX");
        calldatas[15] = _setPendingAdminCalldata;

        targets[16] = addresses.getAddress("mUSDCwh");
        calldatas[16] = _setPendingAdminCalldata;

        targets[17] = addresses.getAddress("mxcUSDC");
        calldatas[17] = _setPendingAdminCalldata;

        targets[18] = addresses.getAddress("mETHwh");
        calldatas[18] = _setPendingAdminCalldata;

        bytes[] memory temporalGovCalldatas = new bytes[](1);
        bytes memory temporalGovExecData;
        {
            address temporalGovAddress = addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                baseChainId
            );
            address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
            uint64 nextSequence = IWormhole(wormholeCore).nextSequence(
                address(governor)
            );
            address[] memory temporalGovTargets = new address[](1);
            temporalGovTargets[0] = temporalGovAddress;

            temporalGovCalldatas[0] = proposalC.temporalGovernanceCalldata(0);

            temporalGovExecData = abi.encode(
                temporalGovAddress,
                temporalGovTargets,
                new uint256[](1), /// 0 value
                temporalGovCalldatas
            );

            vm.prank(addresses.getAddress("BREAK_GLASS_GUARDIAN"));
            vm.expectEmit(true, true, true, true, wormholeCore);
            emit LogMessagePublished(
                address(governor),
                nextSequence,
                1000, /// nonce is hardcoded to 1000 in mip-m18c.sol
                temporalGovExecData,
                200 /// consistency level is hardcoded at 200 in mip-m18c.sol
            );
        }
        governor.executeBreakGlass(targets, calldatas);

        assertEq(
            IStakedWellUplift(addresses.getAddress("stkWELL"))
                .EMISSION_MANAGER(),
            artemisTimelockAddress,
            "stkWELL EMISSIONS MANAGER"
        );
        assertEq(
            Ownable(addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"))
                .owner(),
            artemisTimelockAddress,
            "ecosystem reserve controller owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).pendingOwner(),
            artemisTimelockAddress,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        /// governor still owns, pending is artemis timelock
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).owner(),
            address(governor),
            "WORMHOLE_BRIDGE_ADAPTER_PROXY owner incorrect"
        );
        assertEq(
            Ownable(addresses.getAddress("MOONBEAM_PROXY_ADMIN")).owner(),
            artemisTimelockAddress,
            "MOONBEAM_PROXY_ADMIN owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .owner(),
            address(governor),
            "xWELL_PROXY owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .pendingOwner(),
            artemisTimelockAddress,
            "xWELL_PROXY pending owner incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mETHwh")).pendingAdmin(),
            artemisTimelockAddress,
            "mETHwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mETHwh")).admin(),
            address(governor),
            "mETHwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).admin(),
            address(governor),
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).pendingAdmin(),
            artemisTimelockAddress,
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).admin(),
            address(governor),
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mFRAX")).pendingAdmin(),
            artemisTimelockAddress,
            "mFRAX pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mFRAX")).admin(),
            address(governor),
            "mFRAX admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).admin(),
            address(governor),
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).pendingAdmin(),
            artemisTimelockAddress,
            "mxcDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).admin(),
            address(governor),
            "mxcDOT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).pendingAdmin(),
            artemisTimelockAddress,
            "mGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).admin(),
            address(governor),
            "mGLIMMER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).admin(),
            address(governor),
            "MOONWELL_mUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mBUSD pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).admin(),
            address(governor),
            "MOONWELL_mBUSD admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mwBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).admin(),
            address(governor),
            "MOONWELL_mwBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            artemisTimelockAddress,
            "MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).admin(),
            address(governor),
            "MOONWELL_mETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).pendingAdmin(),
            artemisTimelockAddress,
            "UNITROLLER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).admin(),
            address(governor),
            "UNITROLLER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("CHAINLINK_ORACLE")).admin(),
            artemisTimelockAddress,
            "Chainlink oracle admin incorrect"
        );

        assertEq(
            governor.breakGlassGuardian(),
            address(0),
            "break glass guardian not revoked"
        );

        /// Base simulation, LFG!

        vm.selectFork(baseForkId);
        temporalGov = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
        vm.startPrank(address(temporalGov));

        {
            (bool success, ) = address(temporalGov).call(
                temporalGovCalldatas[0]
            );
            require(success, "temporal gov call failed");
        }

        vm.stopPrank();

        assertTrue(
            temporalGov.isTrustedSender(
                uint16(moonBeamWormholeChainId),
                artemisTimelockAddress
            ),
            "artemis timelock not added as a trusted sender"
        );
    }

    /// staking

    /// - assert assets in ecosystem reserve deplete when rewards are claimed

    function testStakestkWellBaseSucceedsAndReceiveRewards() public {
        vm.selectFork(baseForkId);

        /// prank as the wormhole bridge adapter contract
        ///
        uint256 mintAmount = 1_000_000 * 1e18;
        IStakedWellUplift stkwell = IStakedWellUplift(
            addresses.getAddress("stkWELL_PROXY")
        );
        assertGt(
            stkwell.DISTRIBUTION_END(),
            block.timestamp,
            "distribution end incorrect"
        );
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(0, lastUpdateTimestamp, "lastUpdateTimestamp");
            assertEq(0, emissionsPerSecond, "emissions per second");
            assertEq(0, index, "rewards per second");
        }

        vm.startPrank(stkwell.EMISSION_MANAGER());
        /// distribute 1e18 xWELL per second
        stkwell.configureAsset(1e18, address(stkwell));
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        vm.startPrank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
        xwell.mint(address(this), mintAmount);
        xwell.mint(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"), mintAmount);
        vm.stopPrank();

        uint256 prestkBalance = stkwell.balanceOf(address(this));
        uint256 prexwellBalance = xwell.balanceOf(address(this));
        uint256 preSTKWellTotalSupply = stkwell.totalSupply();

        xwell.approve(address(stkwell), mintAmount);
        stkwell.stake(address(this), mintAmount);

        assertEq(preSTKWellTotalSupply + mintAmount, stkwell.totalSupply());
        assertEq(
            stkwell.balanceOf(address(this)),
            prestkBalance + mintAmount,
            "incorrect stkWELL balance"
        );
        assertEq(
            xwell.balanceOf(address(this)),
            prexwellBalance - mintAmount,
            "incorrect xWELL balance"
        );

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertEq(0, index, "rewards per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }

        vm.warp(block.timestamp + 10 days);

        assertEq(
            stkwell.balanceOf(address(this)),
            mintAmount,
            "incorrect stkWELL balance"
        );
        assertEq(xwell.balanceOf(address(this)), 0, "incorrect xWELL balance");

        uint256 userxWellBalance = xwell.balanceOf(address(this));
        stkwell.claimRewards(address(this), type(uint256).max);

        assertEq(
            xwell.balanceOf(address(this)),
            userxWellBalance + (10 days * 1e18),
            "incorrect xWELL balance after claiming rewards"
        );

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertEq(864000000000000000, index, "rewards per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }
    }

    function testStakestkWellBaseSucceedsAndReceiveRewardsThreeUsers() public {
        vm.selectFork(baseForkId);

        address userOne = address(1);
        address userTwo = address(2);
        address userThree = address(3);

        uint256 userOneAmount = 1_000_000 * 1e18;
        uint256 userTwoAmount = 2_000_000 * 1e18;
        uint256 userThreeAmount = 3_000_000 * 1e18;

        /// prank as the wormhole bridge adapter contract
        ///
        uint256 mintAmount = 1_000_000 * 1e18;
        IStakedWellUplift stkwell = IStakedWellUplift(
            addresses.getAddress("stkWELL_PROXY")
        );
        assertGt(
            stkwell.DISTRIBUTION_END(),
            block.timestamp,
            "distribution end incorrect"
        );
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(0, lastUpdateTimestamp, "lastUpdateTimestamp");
            assertEq(0, emissionsPerSecond, "emissions per second");
            assertEq(0, index, "rewards per second");
        }

        vm.startPrank(stkwell.EMISSION_MANAGER());
        /// distribute 1e18 xWELL per second
        stkwell.configureAsset(1e18, address(stkwell));
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        vm.startPrank(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"));
        xwell.mint(userOne, userOneAmount);
        xwell.mint(userTwo, userTwoAmount);
        xwell.mint(userThree, userThreeAmount);
        xwell.mint(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"), mintAmount);
        vm.stopPrank();

        {
            uint256 prestkBalance = stkwell.balanceOf(userOne);
            uint256 prexwellBalance = xwell.balanceOf(userOne);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userOne);
            xwell.approve(address(stkwell), userOneAmount);
            stkwell.stake(userOne, userOneAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userOneAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userOne),
                prestkBalance + userOneAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userOne),
                prexwellBalance - userOneAmount,
                "incorrect xWELL balance"
            );
        }
        {
            uint256 prestkBalance = stkwell.balanceOf(userTwo);
            uint256 prexwellBalance = xwell.balanceOf(userTwo);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userTwo);
            xwell.approve(address(stkwell), userTwoAmount);
            stkwell.stake(userTwo, userTwoAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userTwoAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userTwo),
                prestkBalance + userTwoAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userTwo),
                prexwellBalance - userTwoAmount,
                "incorrect xWELL balance"
            );
        }
        {
            uint256 prestkBalance = stkwell.balanceOf(userThree);
            uint256 prexwellBalance = xwell.balanceOf(userThree);
            uint256 preSTKWellTotalSupply = stkwell.totalSupply();

            vm.startPrank(userThree);
            xwell.approve(address(stkwell), userThreeAmount);
            stkwell.stake(userThree, userThreeAmount);
            vm.stopPrank();

            assertEq(
                preSTKWellTotalSupply + userThreeAmount,
                stkwell.totalSupply()
            );
            assertEq(
                stkwell.balanceOf(userThree),
                prestkBalance + userThreeAmount,
                "incorrect stkWELL balance"
            );
            assertEq(
                xwell.balanceOf(userThree),
                prexwellBalance - userThreeAmount,
                "incorrect xWELL balance"
            );
        }

        {
            (
                uint128 emissionsPerSecond,
                uint128 lastUpdateTimestamp,
                uint256 index
            ) = stkwell.assets(address(stkwell));

            assertEq(1e18, emissionsPerSecond, "emissions per second");
            assertEq(0, index, "rewards per second");
            assertEq(
                block.timestamp,
                lastUpdateTimestamp,
                "last update timestamp"
            );
        }

        vm.warp(block.timestamp + 10 days);

        assertEq(stkwell.getTotalRewardsBalance(userOne), (10 days * 1e18) / 6);
        assertEq(stkwell.getTotalRewardsBalance(userTwo), (10 days * 1e18) / 3);
        assertEq(
            stkwell.getTotalRewardsBalance(userThree),
            (10 days * 1e18) / 2
        );

        uint256 startingxWELLAmount = xwell.balanceOf(
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
        );
        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userOne);

            vm.prank(userOne);
            stkwell.claimRewards(userOne, type(uint256).max);

            assertEq(
                xwell.balanceOf(userOne),
                startingUserxWellBalance + ((10 days * 1e18) / 6),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userTwo);

            vm.prank(userTwo);
            stkwell.claimRewards(userTwo, type(uint256).max);

            assertEq(
                xwell.balanceOf(userTwo),
                startingUserxWellBalance + ((10 days * 1e18) / 3),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        {
            uint256 startingUserxWellBalance = xwell.balanceOf(userThree);

            vm.prank(userThree);
            stkwell.claimRewards(userThree, type(uint256).max);

            assertEq(
                xwell.balanceOf(userThree),
                startingUserxWellBalance + ((10 days * 1e18) / 2),
                "incorrect xWELL balance after claiming rewards"
            );
        }

        assertEq(
            xwell.balanceOf(addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")),
            startingxWELLAmount - 10 days * 1e18,
            "did not deplete ecosystem reserve"
        );
    }
}
