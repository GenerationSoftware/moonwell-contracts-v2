//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
contract mipm18c is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18C";

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    /// TODO verify these params with Luke before code freeze

    /// @notice duration of the voting period for a proposal
    uint256 public constant votingPeriodSeconds = 3 days;

    /// @notice minimum number of votes cast required for a proposal to pass
    uint256 public constant quorum = 1_000_000 * 1e18;

    /// @notice maximum number of live proposals that a user can have
    uint256 public constant maxUserLiveProposals = 5;

    /// @notice duration of the pause
    uint128 public constant pauseDuration = 10 days;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice threshold of tokens required to create a proposal
    uint256 public constant proposalThreshold = 10_000_000 * 1e18;

    /// @notice duration of the cross chain vote collection period
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;

    /// @notice proposal's actions all happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function buildCalldata(Addresses addresses) private {
        require(
            temporalGovernanceTargets.length == 0,
            "calldata already set in mip-18-c"
        );
        require(
            temporalGovernanceTrustedSenders.length == 0,
            "temporal gov trusted sender already set in mip-18-c"
        );
        require(
            approvedCalldata.length == 0,
            "approved calldata already set in mip-18-c"
        );
        require(
            temporalGovernanceCalldata.length == 0,
            "temporal gov calldata already set in mip-18-c"
        );

        address artemisTimelock = addresses.getAddress("ARTEMIS_TIMELOCK");
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        /// add temporal governor to list
        temporalGovernanceTargets.push(temporalGovernor);

        temporalGovernanceTrustedSenders.push(
            ITemporalGovernor.TrustedSender({
                chainId: moonBeamWormholeChainId, /// this chainId is 16 (moonBeamWormholeChainId) regardless of testnet or mainnet
                addr: artemisTimelock /// this timelock on this chain
            })
        );

        /// new break glass guardian call for adding artemis as an owner of the Temporal Governor

        /// roll back trusted senders to artemis timelock
        /// in reality this just adds the artemis timelock as a trusted sender
        /// a second proposal is needed to revoke the Multichain Governor as a trusted sender
        temporalGovernanceCalldata.push(
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                1000,
                abi.encode(
                    /// target is temporal governor, this passes intended recipient check
                    temporalGovernanceTargets[0],
                    /// sets temporal governor target to itself
                    temporalGovernanceTargets,
                    /// sets values to array filled with 0 values
                    new uint256[](1),
                    /// sets calldata to a call to the setTrustedSenders((uint16,address)[])
                    /// function with artemis timelock as the address and moonbeam wormhole
                    /// chain id as the chain id
                    temporalGovernanceCalldata
                ),
                200
            )
        );

        /// old break glass guardian calls from Artemis Governor

        approvedCalldata.push(
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                artemisTimelock
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature("setAdmin(address)", artemisTimelock)
        );

        approvedCalldata.push(
            abi.encodeWithSignature("setPendingAdmin(address)", artemisTimelock)
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                artemisTimelock
            )
        );

        approvedCalldata.push(
            abi.encodeWithSignature("changeAdmin(address)", artemisTimelock)
        );

        approvedCalldata.push(
            abi.encodeWithSignature(
                "transferOwnership(address)",
                artemisTimelock
            )
        );

        /// TODO add setPendingAdmin(address) ?
    }

    function afterDeploy(Addresses addresses, address) public override {
        buildCalldata(addresses);

        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        /// executing proposal on moonbeam, but this proposal needs an address from base
        address multichainVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        trustedSenders[0].addr = multichainVoteCollection;
        trustedSenders[0].chainId = chainIdToWormHoleId[block.chainid]; /// base wormhole chain id

        MultichainGovernor.InitializeData memory initData;

        initData.well = addresses.getAddress("WELL");
        initData.xWell = addresses.getAddress("xWELL_PROXY");
        initData.stkWell = addresses.getAddress("stkWELL");
        initData.distributor = addresses.getAddress(
            "TOKEN_SALE_DISTRIBUTOR_PROXY"
        );
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.maxUserLiveProposals = maxUserLiveProposals;
        initData.pauseDuration = pauseDuration;

        initData.pauseGuardian = addresses.getAddress(
            "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
        );
        initData.breakGlassGuardian = addresses.getAddress(
            "BREAK_GLASS_GUARDIAN"
        );
        initData.wormholeRelayer = addresses.getAddress(
            "WORMHOLE_BRIDGE_RELAYER"
        );

        require(approvedCalldata.length == 7, "calldata not set");

        governor.initialize(initData, trustedSenders, approvedCalldata);
    }

    function validate(Addresses addresses, address) public override {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        assertEq(
            governor.gasLimit(),
            400_000,
            "incorrect gas limit on multichain governor"
        );

        assertEq(
            governor.proposalThreshold(),
            proposalThreshold,
            "incorrect proposal threshold"
        );
        assertEq(
            governor.crossChainVoteCollectionPeriod(),
            crossChainVoteCollectionPeriod,
            "incorrect cross chain vote collection period"
        );
        assertEq(
            governor.maxUserLiveProposals(),
            maxUserLiveProposals,
            "incorrect max live users proposal period"
        );
        assertEq(governor.quorum(), quorum, "incorrect quorum");
        assertEq(
            governor.votingPeriod(),
            votingPeriodSeconds,
            "incorrect voting period"
        );
        assertEq(
            governor.proposalCount(),
            0,
            "incorrect starting proposalCount"
        );
        assertEq(
            address(governor.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xwell address"
        );
        assertEq(
            address(governor.well()),
            addresses.getAddress("WELL"),
            "incorrect well address"
        );
        assertEq(
            address(governor.stkWell()),
            addresses.getAddress("stkWELL"),
            "incorrect stkWell address"
        );
        assertEq(
            address(governor.distributor()),
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            "incorrect distributor address"
        );
        assertEq(
            governor.getNumLiveProposals(),
            0,
            "incorrect number of live proposals"
        );
        assertEq(
            governor.liveProposals().length,
            0,
            "incorrect live proposals count"
        );
        assertEq(
            address(governor.wormholeRelayer()),
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
            "incorrect wormholeRelayer"
        );
        assertEq(
            governor.breakGlassGuardian(),
            addresses.getAddress("BREAK_GLASS_GUARDIAN"),
            "incorrect break glass guardian"
        );
        assertEq(
            governor.pauseGuardian(),
            addresses.getAddress("MOONBEAM_PAUSE_GUARDIAN_MULTISIG"),
            "incorrect moonbeam pause guardian"
        );
        assertEq(governor.pauseStartTime(), 0, "incorrect pauseStartTime");
        assertEq(
            governor.pauseDuration(),
            pauseDuration,
            "incorrect pauseDuration"
        );
        assertFalse(governor.paused(), "incorrect paused state");
        assertFalse(governor.pauseUsed(), "incorrect pauseUsed state");

        assertEq(
            governor.targetAddress(chainIdToWormHoleId[block.chainid]),
            addresses.getAddress(
                "VOTE_COLLECTION_PROXY",
                sendingChainIdToReceivingChainId[block.chainid]
            ),
            "vote collection proxy not in target address"
        );
        assertEq(
            governor.getAllTargetChainsLength(),
            1,
            "incorrect target chains length"
        );
        assertEq(
            governor.getAllTargetChains()[0],
            chainIdToWormHoleId[block.chainid],
            "incorrect target chains length"
        );
        assertTrue(
            governor.isTrustedSender(
                chainIdToWormHoleId[block.chainid],
                addresses.getAddress(
                    "VOTE_COLLECTION_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "vote collection proxy not trusted sender"
        );

        for (uint256 i = 0; i < approvedCalldata.length; i++) {
            assertTrue(
                governor.whitelistedCalldatas(approvedCalldata[i]),
                "calldata not approved"
            );
        }
    }
}
