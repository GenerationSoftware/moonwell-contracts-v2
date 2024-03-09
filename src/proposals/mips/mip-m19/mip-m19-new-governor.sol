//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";

/// rewrite of mip-m19 to use HybridProposal and generate calldata for
/// the Multichain Governor.
/// forge script src/proposals/mips/mip-m19/mip-m19-new-governor.sol:mipm19newGovernor --fork-url moonbeam -vvv
contract mipm19newGovernor is HybridProposal {
    string public constant name = "MIP-M19";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m19/MIP-M19.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses addresses, address) public override {
        WormholeUnwrapperAdapter wormholeUnwrapperAdapter = new WormholeUnwrapperAdapter();

        addresses.addAddress(
            "WORMHOLE_UNWRAPPER_ADAPTER",
            address(wormholeUnwrapperAdapter),
            true
        );
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        /// @dev Upgrade wormhole bridge adapter to wormhole unwrapper adapter
        _pushHybridAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER")
            ),
            "Upgrade wormhole bridge adapter to wormhole unwrapper adapter",
            true
        );

        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setLockbox(address)",
                addresses.getAddress("xWELL_LOCKBOX")
            ),
            "Set lockbox on wormhole unwrapper adapter",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        _runMoonbeamMultichainGovernor(
            addresses,
            address(100000000),
            addresses.getAddress("WELL"),
            governor
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        validateProxy(
            vm,
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam proxies for wormhole bridge adapter"
        );

        assertEq(
            WormholeUnwrapperAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).lockbox(),
            addresses.getAddress("xWELL_LOCKBOX"),
            "lockbox not correctly set"
        );
    }
}
