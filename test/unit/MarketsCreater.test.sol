// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployLpTokenStakeV1} from "../../script/DeployLpTokenStake.s.sol";
import {MarketsCreater} from "../../src/launch_pad/MarketsCreater.sol";
import {Market} from "../../src/launch_pad/Market.sol";
import {Minecraft} from "../../src/MinecraftCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";

contract MarketsCreaterTest is Test {
    DeployLpTokenStakeV1 deployer;
    address creater;
    address stakeProxy;
    address rewardToken;
    HelperConfig.NetworkConfig config;

    function setUp() public {
        deployer = new DeployLpTokenStakeV1();
        (stakeProxy, config, rewardToken, creater) = deployer.run();
    }

    /*/////////////////////////////////////////////////////////////
                            CONSTRUCTOR  
    /////////////////////////////////////////////////////////////*/
    function testCreaterOwnerShouldBeTheDeployer() public view {
        address expectedOwner = MarketsCreater(creater).owner();
        assertEq(expectedOwner, config.defaultAccount);
    }

    function testShouldSetStakeCorrectly() public view {
        address actualStakeAddr = MarketsCreater(creater).getStakeAddr();
        assertEq(stakeProxy, actualStakeAddr);
    }

    /*/////////////////////////////////////////////////////////////
                         CREATE MARKET  
    /////////////////////////////////////////////////////////////*/
    function testShouldCreateMarketSuccessfully() public {
        vm.prank(config.defaultAccount);
        MarketsCreater(creater).createMarket();
        uint256 actualMarketsNum = MarketsCreater(creater).getMarketsNum();
        address[] memory markets = MarketsCreater(creater).getMarketsFromIndex(
            0,
            1
        );
        assertEq(1, actualMarketsNum);
        assertEq(true, MarketsCreater(creater).queryMarketIsExist(markets[0]));
    }

    function testShouldEmitCreateMarketEvent() public {
        vm.prank(config.defaultAccount);
        vm.recordLogs();
        MarketsCreater(creater).createMarket();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("MarketCreate(address)"));
        assertEq(
            entries[0].topics[1],
            bytes32(
                uint256(
                    uint160(
                        MarketsCreater(creater).getMarketsFromIndex(0, 1)[0]
                    )
                )
            )
        );
    }

    /*/////////////////////////////////////////////////////////////
                            CREATE STALL  
    /////////////////////////////////////////////////////////////*/
    function testShouldCreateStallSuccessfully() public {
        vm.prank(config.defaultAccount);
        MarketsCreater(creater).createMarket();

        address lastMarketAddr = MarketsCreater(creater).getMarketsFromIndex(
            0,
            1
        )[0];

        vm.prank(config.defaultAccount);
        Market(lastMarketAddr).createStall(
            rewardToken,
            config.defaultAccount,
            10,
            10,
            block.timestamp + 100 seconds,
            block.timestamp + 200 seconds,
            block.timestamp + 20 seconds,
            block.timestamp + 80 seconds
        );

        Market.Stall memory stall = Market(lastMarketAddr).getStall();

        assertEq(config.defaultAccount, stall.stallOwner);
        assertEq(rewardToken, stall.stallToken);
    }
}
