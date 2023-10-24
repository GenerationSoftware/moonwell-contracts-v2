pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV1} from "@protocol/views/MoonwellViewsV1.sol";
import {MToken} from "@protocol/MToken.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MoonwellViewsV1Test is Test {
    MoonwellViewsV1 public viewsContract;

    address public constant proxyAdmin = address(1337);

    address public constant comptroller =
        0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180;

    address public constant tokenSaleDistributor =
        address(0x933fCDf708481c57E9FD82f6BAA084f42e98B60e);

    address public constant safetyModule =
        address(0x8568A675384d761f36eC269D695d6Ce4423cfaB1);

    address public constant governanceToken =
        address(0x511aB53F793683763E5a8829738301368a2411E3);

    address public constant nativeMarket =
        0x091608f4e4a15335145be0A279483C0f8E4c7955;

    address public constant user = 0xd7854FC91f16a58D67EC3644981160B6ca9C41B8;

    function setUp() public {
        viewsContract = new MoonwellViewsV1();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address)",
            address(comptroller),
            address(tokenSaleDistributor),
            address(safetyModule),
            address(governanceToken),
            address(nativeMarket)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            proxyAdmin,
            initdata
        );

        /// wire proxy up
        viewsContract = MoonwellViewsV1(address(proxy));
        vm.rollFork(4717310);
    }

    function testComptrollerIsSet() public {
        address _addy = address(viewsContract.comptroller());
        assertEq(_addy, comptroller);
    }

    function testMarketsSize() public {
        MoonwellViewsV1.Market memory _market = viewsContract.getMarketInfo(
            MToken(0x091608f4e4a15335145be0A279483C0f8E4c7955)
        );

        assertEq(_market.isListed, true);
    }

    function testUserVotingPower() public {
        MoonwellViewsV1.UserVotes memory _votes = viewsContract
            .getUserVotingPower(user);

        assertEq(
            _votes.stakingVotes.votingPower +
                _votes.tokenVotes.votingPower +
                _votes.claimsVotes.votingPower,
            5000001 * 1e18
        );
    }

    function testUserStakingInfo() public {
        MoonwellViewsV1.UserStakingInfo memory _stakingInfo = viewsContract
            .getUserStakingInfo(user);

        assertEq(_stakingInfo.pendingRewards, 29708560610101962);
        assertEq(_stakingInfo.totalStaked, 1000000000000000000);
    }

    // function testUserBalances() public {
    //     MoonwellViewsV1.Balances[] memory _balances = viewsContract
    //         .getUserBalances(user);

    //     console.log("_balances length %s", _balances.length);
    //     // Loop through markets and underlying tokens
    //     for (uint index = 0; index < _balances.length; index++) {
    //         console.log(
    //             "_balance %s %s",
    //             _balances[index].amount,
    //             _balances[index].token
    //         );
    //     }
    //     assertEq(_balances.length, 11);
    // }

    function testUserRewards() public {
        MoonwellViewsV1.Rewards[] memory _rewards = viewsContract
            .getUserRewards(user);

        console.log("_Rewards length %s", _rewards.length);
        // Loop through markets and underlying tokens
        for (uint index = 0; index < _rewards.length; index++) {
            console.log(
                "_reward %s %s %s",
                _rewards[index].rewardToken,
                _rewards[index].supplyRewardsAmount,
                _rewards[index].borrowRewardsAmount
            );
        }
        assertEq(_rewards.length, 2);
    }
}
