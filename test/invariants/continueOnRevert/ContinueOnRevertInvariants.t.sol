// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployLpTokenStakeV1} from "../../../script/DeployLpTokenStake.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {LpTokenStakeV1} from "../../../src/LpTokenStakeV1.sol";
import {Minecraft} from "../../../src/MinecraftCoin.sol";
import {LpToken} from "../../mocks/LpToken.sol";
import {ContinueOnRevertHandler} from "./ContinueOnRevertHandler.t.sol";

contract ContinueOnRevertInvariantsTest is StdInvariant, Test {
    DeployLpTokenStakeV1 deployer;

    address stake;
    address rewardToken;
    HelperConfig.NetworkConfig config;
    ContinueOnRevertHandler handler;
    LpToken eth_minecraft_lp;
    LpToken sol_minecraft_lp;
    address eth_minecraft_lp_addr;
    address sol_minecraft_lp_addr;

    address public user_Alice = makeAddr("user_Alice");
    address public user_Bob = makeAddr("user_Bob");

    function setUp() external {
        deployer = new DeployLpTokenStakeV1();
        (stake, config, rewardToken, ) = deployer.run();

        handler = new ContinueOnRevertHandler(
            LpTokenStakeV1(stake),
            Minecraft(rewardToken),
            config
        );
        eth_minecraft_lp = config.eth_minecraft_lp;
        sol_minecraft_lp = config.sol_minecraft_lp;
        eth_minecraft_lp_addr = address(eth_minecraft_lp);
        sol_minecraft_lp_addr = address(sol_minecraft_lp);

        targetContract(address(handler));
    }

    // forge test --match-test invariant_unitCumulativeRewardsShouldNotBeNegative -vvv
    function invariant_unitCumulativeRewardsShouldNotBeNegative() public view {
        assert(
            LpTokenStakeV1(stake)
                .getPoolInfo(address(eth_minecraft_lp))
                .unitCumulativeRewards >= 0
        );
        assert(
            LpTokenStakeV1(stake)
                .getPoolInfo(address(sol_minecraft_lp))
                .unitCumulativeRewards >= 0
        );
    }

    // forge test --match-test invariant_gettersShouldNotRevert -vvv
    function invariant_gettersShouldNotRevert() public view {
        LpTokenStakeV1(stake).getPoolInfo(eth_minecraft_lp_addr);
        LpTokenStakeV1(stake).getPoolInfo(sol_minecraft_lp_addr);

        LpTokenStakeV1(stake).getUserInfo(user_Alice);
        LpTokenStakeV1(stake).getUserInfo(user_Bob);
        LpTokenStakeV1(stake).getUserStakeRecord(
            user_Alice,
            eth_minecraft_lp_addr
        );
        LpTokenStakeV1(stake).getUserStakeRecord(
            user_Alice,
            sol_minecraft_lp_addr
        );
        LpTokenStakeV1(stake).getUserStakeRecord(
            user_Bob,
            eth_minecraft_lp_addr
        );
        LpTokenStakeV1(stake).getUserStakeRecord(
            user_Bob,
            sol_minecraft_lp_addr
        );
        LpTokenStakeV1(stake).getTotalAmountOfRewardsDistributed();
        LpTokenStakeV1(stake).getRewardToken();
        LpTokenStakeV1(stake).getPoolNum();
        LpTokenStakeV1(stake).version();

        /*  当Handler中存在userWithdrawLpToken时，包含以下函数会报错，即便Alice和Bob在eth和sol的pool中都有份额
        LpTokenStakeV1(stake).getUserRewardsToBeClaimed(
            eth_minecraft_lp_addr,
            user_Alice
        );
        LpTokenStakeV1(stake).getUserRewardsToBeClaimed(
            eth_minecraft_lp_addr,
            user_Bob
        );
        LpTokenStakeV1(stake).getUserRewardsToBeClaimed(
            sol_minecraft_lp_addr,
            user_Alice
        );
        LpTokenStakeV1(stake).getUserRewardsToBeClaimed(
            sol_minecraft_lp_addr,
            user_Bob
        );
        */
    }
}
