// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LpTokenStakeV1} from "../../../src/LpTokenStakeV1.sol";
import {Minecraft} from "../../../src/MinecraftCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {LpToken} from "../../mocks/LpToken.sol";

contract StopOnRevertHandler is Test {
    LpTokenStakeV1 stake;
    Minecraft rewardToken;
    HelperConfig.NetworkConfig config;
    LpToken eth_minecraft_lp;
    LpToken sol_minecraft_lp;

    address public user_Alice = makeAddr("user_Alice");
    address public user_Bob = makeAddr("user_Bob");

    constructor(
        LpTokenStakeV1 _stake,
        Minecraft _reward,
        HelperConfig.NetworkConfig memory _config
    ) {
        stake = _stake;
        rewardToken = _reward;
        config = _config;
        eth_minecraft_lp = config.eth_minecraft_lp;
        sol_minecraft_lp = config.sol_minecraft_lp;
        mintUserInitialLpTokenAmount();
    }

    function mintUserInitialLpTokenAmount() private {
        vm.startPrank(config.defaultAccount);
        eth_minecraft_lp.mint(user_Alice, 1000 * 10 ** 18);
        eth_minecraft_lp.mint(user_Bob, 1000 * 10 ** 18);
        sol_minecraft_lp.mint(user_Alice, 1000 * 10 ** 18);
        sol_minecraft_lp.mint(user_Bob, 1000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(user_Alice);
        eth_minecraft_lp.approve(address(stake), 1000 * 10 ** 18);
        sol_minecraft_lp.approve(address(stake), 1000 * 10 ** 18);
        stake.userDepositLpToken(address(eth_minecraft_lp), 1 * 10 ** 18);
        stake.userDepositLpToken(address(sol_minecraft_lp), 1 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(user_Bob);
        eth_minecraft_lp.approve(address(stake), 1000 * 10 ** 18);
        sol_minecraft_lp.approve(address(stake), 1000 * 10 ** 18);
        stake.userDepositLpToken(address(eth_minecraft_lp), 1 * 10 ** 18);
        stake.userDepositLpToken(address(sol_minecraft_lp), 1 * 10 ** 18);
        vm.stopPrank();
    }

    function userDepositLpToken(
        uint256 lpTokenSeed,
        uint256 userSeed,
        uint256 amount
    ) public {
        amount = bound(amount, 1 * 10 ** 18, 5 * 10 ** 18);
        (address lpToken, address user) = _getLpTokenAndUserFromSeed(
            lpTokenSeed,
            userSeed
        );
        vm.prank(user);
        stake.userDepositLpToken(lpToken, amount);
    }

    function userWithdrawLpToken(
        uint256 lpTokenSeed,
        uint256 userSeed,
        uint256 amount
    ) public {
        amount = bound(amount, 1 * 10 ** 18, 50 * 10 ** 18);
        (address lpToken, address user) = _getLpTokenAndUserFromSeed(
            lpTokenSeed,
            userSeed
        );
        vm.prank(user);
        stake.userWithdrawLpToken(lpToken, amount);
    }

    function _getLpTokenAndUserFromSeed(
        uint256 _lpTokenSeed,
        uint256 _userSeed
    ) private view returns (address lpToken, address user) {
        if (_lpTokenSeed % 2 == 0 && _userSeed % 2 == 0) {
            return (address(eth_minecraft_lp), user_Alice);
        } else if (_lpTokenSeed % 2 == 1 && _userSeed % 2 == 0) {
            return (address(sol_minecraft_lp), user_Alice);
        } else if (_lpTokenSeed % 2 == 0 && _userSeed % 2 == 1) {
            return (address(eth_minecraft_lp), user_Bob);
        } else if (_lpTokenSeed % 2 == 1 && _userSeed % 2 == 1) {
            return (address(sol_minecraft_lp), user_Bob);
        }
    }
}
