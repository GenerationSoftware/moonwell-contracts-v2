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

import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";

contract MultichainGovernorUnitTest is MultichainBaseTest {
    event BreakGlassGuardianChanged(address oldValue, address newValue);

    function testGovernorSetup() public {
        assertEq(
            governor.proposalThreshold(),
            proposalThreshold,
            "proposalThreshold"
        );
        assertEq(
            governor.votingPeriod(),
            votingPeriodSeconds,
            "votingPeriodSeconds"
        );
        assertEq(
            governor.votingDelay(),
            votingDelaySeconds,
            "votingDelaySeconds"
        );
        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            crossChainVoteCollectionPeriod,
            "crossChainVoteCollectionPeriod"
        );
        assertEq(governor.quorum(), quorum, "quorum");
        assertEq(
            governor.maxUserLiveProposals(),
            maxUserLiveProposals,
            "maxUserLiveProposals"
        );
        assertEq(governor.pauseDuration(), pauseDuration, "pauseDuration");
        assertEq(governor.pauseGuardian(), pauseGuardian, "pauseGuardian");
        assertFalse(governor.paused(), "paused");
        assertFalse(governor.pauseUsed(), "paused used");
    }

    function testVoteCollectionSetup() public {
        assertEq(
            address(voteCollection.xWell()),
            address(xwell),
            "xWell address"
        );
        assertTrue(
            voteCollection.isTrustedSender(moonbeamChainId, address(governor)),
            "governor address is trusted sender"
        );
        assertEq(
            address(voteCollection.wormholeRelayer()),
            address(wormholeRelayerAdapter),
            "relayer address"
        );
    }

    function testInitLogicFails() public {
        MultichainGovernor.InitializeData memory initData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );

        vm.expectRevert("Initializable: contract is already initialized");

        governorLogic.initialize(initData, trustedSenders, new bytes[](0));
    }

    function testDeployxWell() public {
        MintLimits.RateLimitMidPointInfo[]
            memory newRateLimits = new MintLimits.RateLimitMidPointInfo[](0);

        (, address xwellProxy, ) = deployXWell(
            "XWell",
            "XWELL",
            address(this), //owner
            newRateLimits,
            pauseDuration,
            pauseGuardian
        );

        xwell = xWELL(xwellProxy);
    }

    /// ACL Negative Tests

    /// GOVERNOR
    function testUpdateApprovedCalldataNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateApprovedCalldata("", true);
    }

    function testRemoveExternalChainConfigNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.removeExternalChainConfig(_trustedSenders);
    }

    function testAddExternalChainConfigNonGovernorFails() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        vm.expectRevert("MultichainGovernor: only governor");
        governor.addExternalChainConfig(_trustedSenders);
    }

    function testUpdateProposalThresholdNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateProposalThreshold(1000);
    }

    function testUpdateMaxUserLiveProposalsNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateMaxUserLiveProposals(1000);
    }

    function testUpdateQuorumNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateQuorum(1000);
    }

    function testUpdateVotingPeriodNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateVotingPeriod(1000);
    }

    function testUpdateVotingDelayNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateVotingDelay(1000);
    }

    function testUpdateCrossChainVoteCollectionPeriodNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.updateCrossChainVoteCollectionPeriod(1000);
    }

    function testSetBreakGlassGuardianNonGovernorFails() public {
        vm.expectRevert("MultichainGovernor: only governor");
        governor.setBreakGlassGuardian(address(this));
    }

    /// BREAK GLASS GUARDIAN

    function testExecuteBreakGlassNonBreakGlassGuardianFails() public {
        vm.expectRevert("MultichainGovernor: only break glass guardian");
        governor.executeBreakGlass(new address[](0), new bytes[](0));
    }

    /// PAUSE GUARDIAN
    function testPauseNonPauseGuardianFails() public {
        vm.expectRevert("ConfigurablePauseGuardian: only pause guardian");
        vm.prank(address(1));
        governor.pause();
    }

    /// ACL Positive Tests

    function testUpdateApprovedCalldataGovernorSucceeds() public {
        vm.prank(address(governor));
        governor.updateApprovedCalldata("", true);
        assertTrue(
            governor.whitelistedCalldatas(""),
            "calldata not whitelisted"
        );
    }

    function testRemoveExternalChainConfigGovernorSucceeds() public {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = testAddExternalChainConfigGovernorSucceeds();

        vm.prank(address(governor));
        governor.removeExternalChainConfig(_trustedSenders);

        assertFalse(
            governor.isTrustedSender(
                _trustedSenders[0].chainId,
                _trustedSenders[0].addr
            ),
            "trusted sender not removed"
        );
    }

    function testAddExternalChainConfigGovernorSucceeds()
        public
        returns (WormholeTrustedSender.TrustedSender[] memory)
    {
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        _trustedSenders[0].chainId = 1;
        _trustedSenders[0].addr = address(this);

        vm.prank(address(governor));
        governor.addExternalChainConfig(_trustedSenders);
        assertTrue(
            governor.isTrustedSender(
                _trustedSenders[0].chainId,
                _trustedSenders[0].addr
            ),
            "trusted sender not added"
        );

        return _trustedSenders;
    }

    function testUpdateProposalThresholdGovernorSucceeds() public {
        uint256 newProposalThreshold = Constants.MIN_PROPOSAL_THRESHOLD;

        vm.prank(address(governor));
        governor.updateProposalThreshold(newProposalThreshold);

        assertEq(
            governor.proposalThreshold(),
            newProposalThreshold,
            "proposalThreshold not updated"
        );
    }

    function testUpdateMaxUserLiveProposalsGovernorSucceeds() public {
        uint256 newMaxUserLiveProposals = 4;

        vm.prank(address(governor));
        governor.updateMaxUserLiveProposals(newMaxUserLiveProposals);

        assertEq(
            governor.maxUserLiveProposals(),
            newMaxUserLiveProposals,
            "maxUserLiveProposals not updated"
        );
    }

    function testUpdateQuorumGovernorSucceeds() public {
        uint256 newQuorum = 2_500_000_000 * 1e18;

        vm.prank(address(governor));
        governor.updateQuorum(newQuorum);

        assertEq(governor.quorum(), newQuorum, "quorum not updated");
    }

    function testUpdateVotingPeriodGovernorSucceeds() public {
        uint256 newVotingPeriod = 1 hours;

        vm.prank(address(governor));
        governor.updateVotingPeriod(newVotingPeriod);

        assertEq(
            governor.votingPeriod(),
            newVotingPeriod,
            "votingPeriod not updated"
        );
    }

    function testUpdateVotingDelayGovernorSucceeds() public {
        uint256 newVotingDelay = 1 hours;

        vm.prank(address(governor));
        governor.updateVotingDelay(newVotingDelay);

        assertEq(
            governor.votingDelay(),
            newVotingDelay,
            "votingDelay not updated"
        );
    }

    function testUpdateCrossChainVoteCollectionPeriodGovernorSucceeds() public {
        uint256 newCrossChainVoteCollectionPeriod = 1 hours;
        vm.prank(address(governor));
        governor.updateCrossChainVoteCollectionPeriod(
            newCrossChainVoteCollectionPeriod
        );

        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            newCrossChainVoteCollectionPeriod,
            "crossChainVoteCollectionPeriod not updated"
        );
    }

    function testSetBreakGlassGuardianGovernorSucceeds() public {
        address newBgg = address(1);

        vm.prank(address(governor));
        governor.setBreakGlassGuardian(newBgg);

        assertEq(
            governor.breakGlassGuardian(),
            newBgg,
            "breakGlassGuardian not updated"
        );
    }

    function testExecuteBreakGlassBreakGlassGuardianSucceeds() public {
        address bgg = governor.breakGlassGuardian();

        vm.prank(bgg);
        vm.expectEmit(true, true, true, true, address(governor));
        emit BreakGlassGuardianChanged(bgg, address(0));

        governor.executeBreakGlass(new address[](0), new bytes[](0));

        assertEq(
            governor.breakGlassGuardian(),
            address(0),
            "break glass guardian not reset"
        );
    }

    /// PAUSE GUARDIAN
    function testPausePauseGuardianSucceeds() public {
        vm.warp(block.timestamp + 1);

        vm.prank(governor.pauseGuardian());
        governor.pause();

        assertTrue(governor.paused(), "governor not paused");
        assertTrue(governor.pauseUsed(), "pauseUsed not updated");
        assertEq(governor.pauseStartTime(), block.timestamp, "pauseStartTime");
    }

    function testProposeWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.propose(
            new address[](0),
            new uint256[](0),
            new bytes[](0),
            ""
        );
    }

    function testExecuteWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.execute(0);
    }

    function testCastVoteWhenPausedFails() public {
        testPausePauseGuardianSucceeds();

        vm.expectRevert("Pausable: paused");
        governor.castVote(0, 0);
    }
}
