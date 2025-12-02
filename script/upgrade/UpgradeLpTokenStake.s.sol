// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LpTokenStakeV1} from "../../src/LpTokenStakeV1.sol";
import {LpTokenStakeV2} from "../../src/LpTokenStakeV2.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract UpgradeLpTokenStake is Script {
    function upgradeV1ToV2(
        address proxyAddress,
        address newImp
    ) public returns (address) {
        vm.startBroadcast();
        LpTokenStakeV1 proxy = LpTokenStakeV1(proxyAddress);
        proxy.upgradeToAndCall(address(newImp), "");
        vm.stopBroadcast();
        return address(proxy);
    }
}
