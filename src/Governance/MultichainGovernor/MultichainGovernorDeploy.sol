pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";

contract MultichainGovernorDeploy {
    function deployMultichainGovernor(
        MultichainGovernor.InitializeData memory initializeData,
        WormholeTrustedSender.TrustedSender[] memory trustedSenders
    ) public returns (address proxyAdmin, address proxy, address governorImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize((address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint128,address,address,address),(uint16,address)[])",
            initializeData,
            trustedSenders
        );

        proxyAdmin = address(new ProxyAdmin());
        governorImpl = address(new MultichainGovernor());

        proxy = address(
            new TransparentUpgradeableProxy(governorImpl, proxyAdmin, initData)
        );
    }
}
