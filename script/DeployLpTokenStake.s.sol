// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LpTokenStakeV1} from "../src/LpTokenStakeV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Minecraft} from "../src/MinecraftCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {LpToken} from "../test/mocks/LpToken.sol";
import {MarketsCreater} from "../src/launch_pad/MarketsCreater.sol";

contract DeployLpTokenStakeV1 is Script {
    uint256 public constant INITIAL_REWARD_SUPPLY = 10000000 * 10 ** 18;

    function run()
        external
        returns (
            address stake,
            HelperConfig.NetworkConfig memory config,
            address rewardTokenAddress,
            address marketsCreaterAddress
        )
    {
        HelperConfig helperConfig = new HelperConfig();

        config = helperConfig.getConfig(block.chainid);

        vm.startBroadcast(config.defaultAccount);
        Minecraft rewardToken = new Minecraft();
        LpTokenStakeV1 stakeV1 = new LpTokenStakeV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(stakeV1), "");

        MarketsCreater marketsCreater = new MarketsCreater(address(proxy));

        LpTokenStakeV1(address(proxy)).initialize(
            address(rewardToken),
            address(marketsCreater)
        );
        rewardToken.mint(address(proxy), INITIAL_REWARD_SUPPLY);
        vm.stopBroadcast();
        return (
            address(proxy),
            config,
            address(rewardToken),
            address(marketsCreater)
        );
    }
}
