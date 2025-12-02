// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployLpTokenStakeV1} from "../../script/DeployLpTokenStake.s.sol";
import {LpTokenStakeV1} from "../../src/LpTokenStakeV1.sol";
import {LpToken} from "../mocks/LpToken.sol";
import {Minecraft} from "../../src/MinecraftCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Cal} from "../../src/libCal.sol";

contract LpTokenStakeTest is Test {
    DeployLpTokenStakeV1 deployer;
    address proxyAddress;
    address rewardTokenAddress;

    LpTokenStakeV1 stake;
    LpToken eth_minecraft_lp;
    LpToken sol_minecraft_lp;
    Minecraft rewardToken;

    // 一个池子默认一天消耗 86400 个reward token

    uint256 public constant LPTOKEN_AMOUNT = 100 * 10 ** 18;

    address public user_Alice = makeAddr("Alice");
    address public user_Bob = makeAddr("Bob");

    modifier mintUserInitialLpTokenAmount() {
        _;
        eth_minecraft_lp.mint(user_Alice, LPTOKEN_AMOUNT);
        eth_minecraft_lp.mint(user_Bob, LPTOKEN_AMOUNT);
        sol_minecraft_lp.mint(user_Alice, LPTOKEN_AMOUNT);
        sol_minecraft_lp.mint(user_Bob, LPTOKEN_AMOUNT);
        vm.startPrank(user_Alice);
        eth_minecraft_lp.approve(address(stake), LPTOKEN_AMOUNT);
        sol_minecraft_lp.approve(address(stake), LPTOKEN_AMOUNT);
        vm.stopPrank();
        vm.startPrank(user_Bob);
        eth_minecraft_lp.approve(address(stake), LPTOKEN_AMOUNT);
        sol_minecraft_lp.approve(address(stake), LPTOKEN_AMOUNT);
        vm.stopPrank();
    }

    function setUp() public mintUserInitialLpTokenAmount {
        deployer = new DeployLpTokenStakeV1();
        HelperConfig.NetworkConfig memory config;
        (proxyAddress, config, rewardTokenAddress, ) = deployer.run();
        eth_minecraft_lp = config.eth_minecraft_lp;
        sol_minecraft_lp = config.sol_minecraft_lp;
        rewardToken = Minecraft(rewardTokenAddress);
        stake = LpTokenStakeV1(proxyAddress);
        vm.prank(stake.owner());
        stake.transferOwnership(address(this));

        vm.prank(rewardToken.owner());
        rewardToken.transferOwnership(address(this));

        vm.prank(eth_minecraft_lp.owner());
        eth_minecraft_lp.transferOwnership(address(this));
        vm.prank(sol_minecraft_lp.owner());
        sol_minecraft_lp.transferOwnership(address(this));
    }

    /*/////////////////////////////////////////////////////////////
                            INITIALIZE  
    /////////////////////////////////////////////////////////////*/
    function testInitializeStakeContract() public view {
        assertEq(stake.getRewardToken(), rewardTokenAddress);
        assertEq(
            rewardToken.balanceOf(proxyAddress),
            deployer.INITIAL_REWARD_SUPPLY() // DeployLpTokenStakeV1.INITIAL_REWARD_SUPPLY 不行
        );
    }

    /*/////////////////////////////////////////////////////////////
                            CREATE POOL  
    /////////////////////////////////////////////////////////////*/
    function testFirstDepositCanCreatePoolAndEmitEvent() public {
        vm.expectEmit(true, true, false, true, address(stake));
        emit LpTokenStakeV1.PoolCreated(
            address(eth_minecraft_lp),
            block.timestamp
        );
        vm.prank(user_Alice);
        stake.userDepositLpToken(address(eth_minecraft_lp), LPTOKEN_AMOUNT);
        vm.prank(user_Bob);
        stake.userDepositLpToken(address(sol_minecraft_lp), LPTOKEN_AMOUNT);
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        LpTokenStakeV1.UserInfo memory alice = stake.getUserInfo(user_Alice);
        LpTokenStakeV1.UserInfo memory bob = stake.getUserInfo(user_Bob);

        assertEq(stake.getPoolNum(), 2);
        assertEq(eth_lp.stakeLpToken, address(eth_minecraft_lp));
        assertEq(eth_lp.totalDepositAmount, LPTOKEN_AMOUNT);
        assertEq(eth_lp.isLocked, false);
        assertEq(alice.userAssetArr[0].stakeLpToken, address(eth_minecraft_lp));
        assertEq(bob.userAssetArr[0].stakeLpToken, address(sol_minecraft_lp));
    }

    /*/////////////////////////////////////////////////////////////
                           USER DEPOSIT LPTOKEN
    /////////////////////////////////////////////////////////////*/
    modifier createPool() {
        vm.prank(user_Alice);
        stake.userDepositLpToken(address(eth_minecraft_lp), 1 * 10 ** 18);
        vm.prank(user_Bob);
        stake.userDepositLpToken(address(eth_minecraft_lp), 3 * 10 ** 18);
        _;
    }

    function testLpTokenAmountChangeShouldEmitEvent() public {
        vm.expectEmit(true, true, false, true, address(stake));
        emit LpTokenStakeV1.UserDeposit(
            address(eth_minecraft_lp),
            user_Alice,
            10 * 10 ** 18
        );
        vm.prank(user_Alice);
        stake.userDepositLpToken(address(eth_minecraft_lp), 10 * 10 ** 18);

        vm.expectEmit(true, true, false, true, address(stake));
        emit LpTokenStakeV1.UserWithdraw(
            address(eth_minecraft_lp),
            user_Alice,
            5 * 10 ** 18
        );
        vm.prank(user_Alice);
        stake.userWithdrawLpToken(address(eth_minecraft_lp), 5 * 10 ** 18);
    }

    function testFuzzShouldReturnAmountOfUserDepositedInPool(
        uint256 aliceDepositedInEthLpPool,
        uint256 bobDepositedInEthLpPool
    ) public createPool {
        aliceDepositedInEthLpPool = bound(
            aliceDepositedInEthLpPool,
            1 ether,
            10 ether
        );
        bobDepositedInEthLpPool = bound(
            bobDepositedInEthLpPool,
            1 ether,
            10 ether
        );
        vm.prank(user_Alice);
        stake.userDepositLpToken(
            address(eth_minecraft_lp),
            aliceDepositedInEthLpPool
        );
        vm.prank(user_Bob);
        stake.userDepositLpToken(
            address(eth_minecraft_lp),
            bobDepositedInEthLpPool
        );

        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        LpTokenStakeV1.UserInfo memory alice = stake.getUserInfo(user_Alice);
        LpTokenStakeV1.UserInfo memory bob = stake.getUserInfo(user_Bob);
        uint256 expectedDepositedAmount = alice.userAssetArr[0].amount +
            bob.userAssetArr[0].amount;
        assertEq(expectedDepositedAmount, eth_lp.totalDepositAmount);
    }

    function testFuzzunitCumulativeRewardsAndLastUpdateTimeShouldBeUpdateCorrectly()
        public
        createPool
    {
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        uint256 timestamp = eth_lp.lastUpdateTime;

        uint256 duration;
        duration = bound(duration, 10 seconds, 1800 seconds);

        vm.warp(timestamp + duration);
        uint256 currentBlockNum = block.number + 1;
        vm.roll(currentBlockNum);
        eth_lp = stake.getPoolInfo(address(eth_minecraft_lp));

        uint256 expectedUnitCumulativeRewards = Cal.calNewUnitCumulativeRewards(
            0,
            eth_lp.rewardPerSec * duration,
            4 * 10 ** 18
        );

        assertEq(expectedUnitCumulativeRewards, eth_lp.unitCumulativeRewards);
        assertEq(block.timestamp, eth_lp.lastUpdateTime);
    }

    function testFuzzRewardsShouldBeCalculateCorrectly() public createPool {
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        uint256 duration;
        duration = bound(duration, 10 seconds, 1800 seconds);

        vm.warp(eth_lp.lastUpdateTime + duration);
        uint256 currentBlockNum = block.number + 1;
        vm.roll(currentBlockNum);
        (uint256 actualRewardAmount, ) = stake.getUserRewardsToBeClaimed(
            address(eth_minecraft_lp),
            user_Alice
        );

        eth_lp = stake.getPoolInfo(address(eth_minecraft_lp));

        uint256 expectedRewardAmount = Cal
            .calRewardsGeneratedSinceTheLastOperation(
                eth_lp.unitCumulativeRewards,
                0,
                1 * 10 ** 18
            );

        assertEq(expectedRewardAmount, actualRewardAmount);
    }

    function testFuzzTotalAmountChangeRewardsShouldBeCalculateCorrectly()
        public
        createPool
    {
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        uint256 firstDuration;
        firstDuration = bound(firstDuration, 10 seconds, 1800 seconds);

        vm.warp(eth_lp.lastUpdateTime + firstDuration);
        uint256 currentBlockNum = block.number + 1;
        vm.roll(currentBlockNum);

        (uint256 firstDurationRewardAmount, ) = stake.getUserRewardsToBeClaimed(
            address(eth_minecraft_lp),
            user_Alice
        );
        // vm.prank(user_Alice);
        // stake.userDepositLpToken(address(eth_minecraft_lp), 2 * 10 ** 18);
        vm.prank(user_Bob);
        stake.userWithdrawLpToken(address(eth_minecraft_lp), 2 * 10 ** 18);

        uint256 secondDuration;
        secondDuration = bound(secondDuration, 10 seconds, 1800 seconds);
        vm.warp(eth_lp.lastUpdateTime + firstDuration + secondDuration);
        vm.roll(currentBlockNum + 1);
        (uint256 secondDurationRewardAmount, ) = stake
            .getUserRewardsToBeClaimed(address(eth_minecraft_lp), user_Alice);

        uint256 actualRewardAmount = secondDurationRewardAmount -
            firstDurationRewardAmount;
        uint256 expectedRewardAmount = (1 * 10 ** 18 * secondDuration) / 2;

        assertApproxEqAbs(expectedRewardAmount, actualRewardAmount, 1);
    }

    function testWithdrawLpTokenEnableToEffectUserInfo() public createPool {
        LpTokenStakeV1.UserInfo memory bob = stake.getUserInfo(user_Bob);
        assertEq(1, bob.userAssetArr.length);
        assertEq(
            true,
            stake.getUserStakeRecord(address(eth_minecraft_lp), user_Bob)
        );

        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        vm.warp(eth_lp.lastUpdateTime + 10 seconds);
        uint256 currentBlockNum = block.number + 1;
        vm.roll(currentBlockNum);

        vm.prank(user_Bob);
        stake.userWithdrawLpToken(address(eth_minecraft_lp), 3 * 10 ** 18);
        bob = stake.getUserInfo(user_Bob);

        assertEq(0, bob.userAssetArr.length);
        assertEq(
            false,
            stake.getUserStakeRecord(address(eth_minecraft_lp), user_Bob)
        );
        assertEq(7.5 * 10 ** 18, rewardToken.balanceOf(user_Bob));
        assertEq(
            rewardToken.balanceOf(user_Bob),
            stake.getTotalAmountOfRewardsDistributed()
        );
    }

    function testUserCanClaimRewardsSuccessfully() public createPool {
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );

        vm.warp(eth_lp.lastUpdateTime + 10 seconds);
        uint256 currentBlockNum = block.number + 1;
        vm.roll(currentBlockNum);

        vm.expectEmit(true, true, false, true, address(stake));
        emit LpTokenStakeV1.UserClaimRewards(
            address(eth_minecraft_lp),
            user_Alice,
            1 * 10 ** 18
        );
        vm.prank(user_Alice);
        stake.userClaimRewards(address(eth_minecraft_lp), 1 * 10 ** 18);

        LpTokenStakeV1.Asset memory aliceEthLpAsset = stake
            .getUserInfo(user_Alice)
            .userAssetArr[0];

        assertEq(aliceEthLpAsset.rewardsToBeClaimed, 1.5 * 10 ** 18);
        assertEq(aliceEthLpAsset.rewardHadBeenClaimed, 1 * 10 ** 18);

        vm.warp(eth_lp.lastUpdateTime + 20 seconds);
        vm.roll(currentBlockNum + 1);
        (uint256 lastRewardsToBeClaimed, ) = stake.getUserRewardsToBeClaimed(
            address(eth_minecraft_lp),
            user_Alice
        );
        assertEq(4 * 10 ** 18, lastRewardsToBeClaimed);
    }

    function testCanChangePoolStatusSuccessfully() public createPool {
        stake.setPoolStatus(address(eth_minecraft_lp), true);
        stake.setPoolRewardPerSec(address(eth_minecraft_lp), 2 * 10 ** 18);
        LpTokenStakeV1.PoolInfo memory eth_lp = stake.getPoolInfo(
            address(eth_minecraft_lp)
        );
        assertEq(true, eth_lp.isLocked);
        assertEq(2 * 10 ** 18, eth_lp.rewardPerSec);
    }
}
