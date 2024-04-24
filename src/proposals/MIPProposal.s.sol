// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@proposals/Addresses.sol";

/*
How to use:
forge script src/proposals/MIPProposal.s.sol:DeployProposal \
    -vvvv \
    --rpc-url $ETH_RPC_URL \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.

to verify after deploy:
  forge verify-contract --etherscan-api-key $BASESCAN_API_KEY \ 
        <deployed contract address> src/MWethDelegate.sol:MWethDelegate
        --chain 8453

*/
abstract contract MIPProposal is Script {
    uint256 private PRIVATE_KEY;
    Addresses private addresses;

    bool private DEBUG;
    bool private DO_DEPLOY;
    bool private DO_AFTER_DEPLOY;
    bool private DO_AFTER_DEPLOY_SETUP;
    bool private DO_BUILD;
    bool private DO_RUN;
    bool private DO_TEARDOWN;
    bool private DO_VALIDATE;
    bool private DO_PRINT;

    constructor() {
        PRIVATE_KEY = uint256(vm.envOr("ETH_PRIVATE_KEY", uint256(123)));

        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_AFTER_DEPLOY_SETUP = vm.envOr("DO_AFTER_DEPLOY_SETUP", true);
        DO_BUILD = vm.envOr("DO_BUILD", true);
        DO_RUN = vm.envOr("DO_RUN", true);
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", true);
        DO_VALIDATE = vm.envOr("DO_VALIDATE", true);
        DO_PRINT = vm.envOr("DO_PRINT", true);

        addresses = new Addresses();
        vm.makePersistent(address(addresses));
    }

    function run() public virtual {
        vm.selectFork(primaryForkId());

        address deployerAddress = vm.addr(PRIVATE_KEY);

        console.log("deployerAddress: ", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);
        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY_SETUP) afterDeploySetup(addresses);
        vm.stopBroadcast();

        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        /// todo print out actual proposal calldata
        if (DO_PRINT) {
            printCalldata(addresses);
            printProposalActionSteps();
        }

        if (DO_DEPLOY) {
            {
                (
                    string[] memory recordedNames,
                    ,
                    address[] memory recordedAddresses
                ) = addresses.getRecordedAddresses();

                if (recordedNames.length != 0) {
                    console.log("New addresses after deploy:");
                }

                for (uint256 j = 0; j < recordedNames.length; j++) {
                    console.log(
                        "{\n        'addr': '%s', ",
                        recordedAddresses[j]
                    );
                    console.log("        'chainId': %d,", block.chainid);
                    console.log("        'isContract': %s", true, ",");
                    console.log(
                        "        'name': '%s'\n}%s",
                        recordedNames[j],
                        j < recordedNames.length - 1 ? "," : ""
                    );
                }
            }

            {
                (
                    string[] memory recordedNames,
                    uint256[] memory chainIds,
                    address[] memory oldRecordedAddresses,
                    address[] memory newRecordedAddresses
                ) = addresses.getChangedAddresses();

                if (recordedNames.length != 0) {
                    console.log("Addresses Changed after deploy:");
                }

                for (uint256 j = 0; j < recordedNames.length; j++) {
                    console.log(
                        "%s on chainid %d changed ",
                        recordedNames[j],
                        chainIds[j]
                    );

                    console.log(
                        "    %s -> %s\n",
                        oldRecordedAddresses[j],
                        newRecordedAddresses[j]
                    );
                }

                if (recordedNames.length != 0) {
                    console.log("\nNew Addresses JSON\n");
                }

                for (uint256 j = 0; j < recordedNames.length; j++) {
                    console.log(
                        "{\n        'addr': '%s', ",
                        newRecordedAddresses[j]
                    );
                    console.log("        'chainId': %d,", chainIds[j]);
                    console.log("        'isContract': %s", true, ",");
                    console.log(
                        "        'name': '%s'\n}%s",
                        newRecordedAddresses[j],
                        j < newRecordedAddresses.length - 1 ? "," : ""
                    );
                }
            }
        }
    }

    function name() external view virtual returns (string memory);

    function primaryForkId() public view virtual returns (uint256) {
        return 0;
    }

    function deploy(Addresses, address) public virtual;

    function afterDeploy(Addresses, address) public virtual;

    function afterDeploySetup(Addresses) public virtual;

    function build(Addresses) public virtual;

    function run(Addresses, address) public virtual;

    function printCalldata(Addresses addresses) public virtual;

    function teardown(Addresses, address) public virtual;

    function validate(Addresses, address) public virtual;

    function printProposalActionSteps() public virtual;
}
