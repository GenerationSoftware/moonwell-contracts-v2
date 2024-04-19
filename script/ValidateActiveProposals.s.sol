pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ITemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Script} from "@forge-std/Script.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";

contract ValidateActiveProposals is Script, Test, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice fork ID for base
    uint256 public baseForkId =
        vm.createFork(vm.envOr("BASE_RPC_URL", string("base")));

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envOr("MOONBEAM_RPC_URL", string("moonbeam")));

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        vm.selectFork(moonbeamForkId);
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        uint256[] memory proposalIds = governor.liveProposals();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            uint256 proposalId = proposalIds[i];
            (address[] memory targets, , bytes[] memory calldatas) = governor
                .getProposalData(proposalId);

            for (uint256 j = 0; j < targets.length; j++) {
                require(
                    targets[j].code.length > 0,
                    "Proposal target not a contract"
                );

                {
                    // Simulate proposals execution
                    (
                        ,
                        uint256 voteSnapshotTimestamp,
                        uint256 votingStartTime,
                        ,
                        uint256 crossChainVoteCollectionEndTimestamp,
                        ,
                        ,
                        ,

                    ) = governor.proposalInformation(proposalId);

                    address well = addresses.getAddress("xWELL_PROXY");
                    vm.warp(voteSnapshotTimestamp - 1);
                    deal(well, address(this), governor.quorum());
                    xWELL(well).delegate(address(this));

                    vm.warp(votingStartTime);
                    governor.castVote(proposalId, 0);

                    vm.warp(crossChainVoteCollectionEndTimestamp + 1);

                    governor.execute(proposalId);
                }
            }

            // Check if there is any action on Base
            address wormholeCore = block.chainid == moonBeamChainId
                ? addresses.getAddress("WORMHOLE_CORE_MOONBEAM")
                : addresses.getAddress("WORMHOLE_CORE_MOONBASE");

            uint256 lastIndex = targets.length - 1;

            if (targets[lastIndex] == wormholeCore) {
                // decode calldatas
                (, bytes memory payload, ) = abi.decode(
                    slice(
                        calldatas[lastIndex],
                        4,
                        calldatas[lastIndex].length - 4
                    ),
                    (uint32, bytes, uint8)
                );
                address expectedTemporalGov = block.chainid == moonBeamChainId
                    ? addresses.getAddress("TEMPORAL_GOVERNOR", baseChainId)
                    : addresses.getAddress(
                        "TEMPORAL_GOVERNOR",
                        baseSepoliaChainId
                    );

                {
                    // decode payload
                    (
                        address temporalGovernorAddress,
                        address[] memory targets,
                        uint256[] memory values,
                        bytes[] memory payloads
                    ) = abi.decode(
                            payload,
                            (address, address[], uint256[], bytes[])
                        );

                    require(
                        temporalGovernorAddress == expectedTemporalGov,
                        "Temporal Governor address mismatch"
                    );
                }

                vm.selectFork(baseForkId);

                bytes memory vaa = generateVAA(
                    uint32(block.timestamp),
                    uint16(chainIdToWormHoleId[baseChainId]),
                    addressToBytes(address(governor)),
                    payload
                );

                ITemporalGovernor temporalGovernor = ITemporalGovernor(
                    expectedTemporalGov
                );

                temporalGovernor.queueProposal(vaa);

                vm.warp(block.timestamp + temporalGovernor.proposalDelay());

                temporalGovernor.executeProposal(vaa);
            }
        }
    }

    /// @dev utility function to generate a Wormhole VAA payload excluding the guardians signature
    function generateVAA(
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        bytes memory payload
    ) private pure returns (bytes memory encodedVM) {
        uint64 sequence = 200;
        uint8 version = 1;
        uint256 nonce = 1;
        uint256 consistencyLevel = 200;

        encodedVM = abi.encodePacked(
            version,
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );
    }

    /// @dev utility function to convert an address to bytes32
    function addressToBytes(address addr) public pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }

    // Utility function to slice bytes array
    function slice(
        bytes memory data,
        uint start,
        uint length
    ) internal pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }
}
