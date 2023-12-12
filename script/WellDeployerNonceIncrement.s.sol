pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";

/*
 to simulate:
    forge script script/WellDeployerNonceIncrement.s.sol:WellDeployerNonceIncrement \
     \ -vvvvv --rpc-url base --with-gas-price 500000
 to run:
    forge script script/WellDeployerNonceIncrement.s.sol:WellDeployerNonceIncrement \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
contract WellDeployerNonceIncrement is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);

        /// send all 2 tx's
        for (uint256 i = 0; i < 2; i++) {
            (bool success, ) = address(deployerAddress).call{value: 1}("");
            success;
            // console.log(vm.getNonce(deployerAddress));
        }
        vm.stopBroadcast();

        /// should have sent 455 transactions, leaving nonce at 440
        assertEq(vm.getNonce(deployerAddress), 455, "incorrect nonce");
    }
}
