// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LpTokenStakeV1} from "../../src/LpTokenStakeV1.sol";
import {LpTokenStakeV2} from "../../src/LpTokenStakeV2.sol";
import {DeployLpTokenStakeV1} from "../../script/DeployLpTokenStake.s.sol";
import {UpgradeLpTokenStake} from "../../script/upgrade/UpgradeLpTokenStake.s.sol";

contract UUPSUpgradeTest is Test {
    DeployLpTokenStakeV1 public deployer;
    UpgradeLpTokenStake public upgrader;

    address public proxy;

    function setUp() public {
        deployer = new DeployLpTokenStakeV1();
        upgrader = new UpgradeLpTokenStake();
        (proxy, , , ) = deployer.run();
    }

    function testUpgradesSuccessful() public {
        assertEq(LpTokenStakeV1(proxy).version(), 1);
        LpTokenStakeV2 stakeV2 = new LpTokenStakeV2();
        upgrader.upgradeV1ToV2(proxy, address(stakeV2));
        assertEq(LpTokenStakeV2(proxy).version(), 2);
    }
}
