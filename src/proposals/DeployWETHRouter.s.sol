// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@proposals/Addresses.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";

/*
How to use:
forge script src/proposals/DeployWETHRouter.s.sol:DeployWETHRouter \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployWETHRouter is Script {
    uint256 public PRIVATE_KEY;
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        console.log("deployer address: ", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);

        WETHRouter router = new WETHRouter(
            WETH9(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH"))
        );

        console.log("router address: ", address(router));

        vm.stopBroadcast();
    }
}
