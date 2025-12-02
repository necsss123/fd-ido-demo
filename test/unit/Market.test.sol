// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployLpTokenStakeV1} from "../../script/DeployLpTokenStake.s.sol";
import {MarketsCreater} from "../../src/launch_pad/MarketsCreater.sol";
import {Market} from "../../src/launch_pad/Market.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LpToken} from "../mocks/LpToken.sol";

contract MarketTest is Test {
    DeployLpTokenStakeV1 deployer;
    address stakeProxy;
    address creater;
    address lastMarketAddr;
    HelperConfig.NetworkConfig config;
    LpToken ppToken; // 项目方token

    address public project_party = makeAddr("project_party");
    address public user_Alice = makeAddr("user_Alice");

    function setUp() public {
        deployer = new DeployLpTokenStakeV1();
        (stakeProxy, config, , creater) = deployer.run();
        ppToken = config.eth_minecraft_lp;
        vm.startPrank(config.defaultAccount);
        ppToken.mint(project_party, 3000 * 10 ** 18);
        MarketsCreater(creater).createMarket();
        vm.stopPrank();
        vm.deal(user_Alice, 100 ether);
        lastMarketAddr = MarketsCreater(creater).getMarketsFromIndex(0, 1)[0];
    }

    /*/////////////////////////////////////////////////////////////
                            CONSTRUCTOR  
    /////////////////////////////////////////////////////////////*/
    function testShouldNotAllowNonDeployerToCreateStall() public {
        vm.prank(project_party);
        vm.expectRevert(bytes("Can only call by admin."));
        Market(lastMarketAddr).createStall(
            address(ppToken),
            project_party,
            10,
            10,
            block.timestamp + 100 seconds,
            block.timestamp + 200 seconds,
            block.timestamp + 20 seconds,
            block.timestamp + 80 seconds
        );
    }

    function testShoudlEmitEventWhenStallAreCreate() public {
        vm.prank(config.defaultAccount);
        vm.expectEmit(true, true, false, true, lastMarketAddr);
        emit Market.StallCreate(address(ppToken), project_party);
        Market(lastMarketAddr).createStall(
            address(ppToken),
            project_party,
            0.1 * 10 ** 18,
            3000 * 10 ** 18,
            block.timestamp + 100 seconds,
            block.timestamp + 200 seconds,
            block.timestamp + 10 seconds,
            block.timestamp + 90 seconds
        );
    }

    modifier getTheLastestMarketAndCreateStall() {
        vm.prank(config.defaultAccount);
        Market(lastMarketAddr).createStall(
            address(ppToken),
            project_party,
            0.1 * 10 ** 18,
            3000 * 10 ** 18,
            block.timestamp + 100 seconds,
            block.timestamp + 200 seconds,
            block.timestamp + 10 seconds,
            block.timestamp + 90 seconds
        );
        _;
    }

    function testInitializesTheIceFrogSaleCorrectly()
        public
        getTheLastestMarketAndCreateStall
    {
        assertEq(
            Market(lastMarketAddr).getStakeAddr(),
            MarketsCreater(creater).getStakeAddr()
        );
        assertEq(Market(lastMarketAddr).getMarketsCreaterAddr(), creater);
        assertEq(
            Market(lastMarketAddr).getStall().stallToken,
            address(ppToken)
        );
        assertEq(Market(lastMarketAddr).getStall().stallOwner, project_party);
    }

    /*/////////////////////////////////////////////////////////////
                            SET VESTING PARAMS  
    /////////////////////////////////////////////////////////////*/
    function testShouldSetVestingParamsCorrectly()
        public
        getTheLastestMarketAndCreateStall
    {
        vm.prank(config.defaultAccount);
        Market(lastMarketAddr).setVestingParams(
            [
                block.timestamp + 300,
                block.timestamp + 400,
                block.timestamp + 500
            ],
            [uint256(3333), uint256(3333), uint256(3334)],
            10000
        );

        uint256[3] memory expectedTimes = [
            block.timestamp + 300,
            block.timestamp + 400,
            block.timestamp + 500
        ];

        uint256[3] memory actualTimes = Market(lastMarketAddr)
            .getStall()
            .vestingPortionsUnlockTime;

        for (uint256 i = 0; i < 3; i++) {
            assertEq(actualTimes[i], expectedTimes[i]);
        }
    }

    function testShouldEmitEventWhenSetVestingParams()
        public
        getTheLastestMarketAndCreateStall
    {
        vm.prank(config.defaultAccount);
        vm.expectEmit(true, false, false, true);
        emit Market.VestingParamsSet(address(ppToken));
        Market(lastMarketAddr).setVestingParams(
            [
                block.timestamp + 300,
                block.timestamp + 400,
                block.timestamp + 500
            ],
            [uint256(3333), uint256(3333), uint256(3334)],
            10000
        );
    }

    /*/////////////////////////////////////////////////////////////
                        DEPOSIT TOKENS  
    /////////////////////////////////////////////////////////////*/
    function testShouldAllowStallOwnerToDepositPPTokens()
        public
        getTheLastestMarketAndCreateStall
    {
        vm.startPrank(project_party);
        ppToken.approve(lastMarketAddr, 3000 * 10 ** 18);
        Market(lastMarketAddr).stallerOwnerDepositStallToken();
        vm.stopPrank();
        assertEq(ppToken.balanceOf(lastMarketAddr), 3000 * 10 ** 18);
    }

    function testShouldEmitEventWhenStallOwnerDepositPPTokens()
        public
        getTheLastestMarketAndCreateStall
    {
        vm.startPrank(project_party);
        ppToken.approve(lastMarketAddr, 3000 * 10 ** 18);
        vm.expectEmit(true, true, false, true, lastMarketAddr);
        emit Market.StallTokenDeposite(project_party, block.timestamp);
        Market(lastMarketAddr).stallerOwnerDepositStallToken();
        vm.stopPrank();
        assertEq(ppToken.balanceOf(lastMarketAddr), 3000 * 10 ** 18);
    }

    /*/////////////////////////////////////////////////////////////
                        REGISTER FOR STALL  
    /////////////////////////////////////////////////////////////*/

    modifier registerForStall() {
        bytes32 msgHash = keccak256(
            abi.encodePacked(user_Alice, lastMarketAddr)
        );
        bytes32 ethSignedMsgHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            config.deployerKey,
            ethSignedMsgHash
        );

        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 1);

        vm.prank(user_Alice);
        Market(lastMarketAddr).registerForStall(sig);
        _;
    }

    function testShouldRegisterForStallSuccessfully()
        public
        getTheLastestMarketAndCreateStall
        registerForStall
    {
        assertEq(Market(lastMarketAddr).getStall().numOfRegistrants, 1);
        assertEq(Market(lastMarketAddr).s_isRegistered(user_Alice), true);
    }

    /*/////////////////////////////////////////////////////////////
                        CHECK PARTICIPATION SIGNATURE   
    /////////////////////////////////////////////////////////////*/
    function testShouldSucceedForValidSignature()
        public
        getTheLastestMarketAndCreateStall
    {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                user_Alice,
                uint256(100 * 10 ** 18),
                lastMarketAddr
            )
        );
        bytes32 ethSignedMsgHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            config.deployerKey,
            ethSignedMsgHash
        );

        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(
            Market(lastMarketAddr).checkParticipationSignature(
                sig,
                user_Alice,
                100 * 10 ** 18
            ),
            true
        );
    }

    /*/////////////////////////////////////////////////////////////
                         PURCHASING   
    /////////////////////////////////////////////////////////////*/
    modifier participationInPurchasing() {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                user_Alice,
                uint256(100 * 10 ** 18),
                lastMarketAddr
            )
        );
        bytes32 ethSignedMsgHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            config.deployerKey,
            ethSignedMsgHash
        );

        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(block.timestamp + 110);
        vm.roll(block.number + 2);

        vm.prank(user_Alice);
        Market(lastMarketAddr).userParticipationInPurchasing{value: 10 ether}(
            sig,
            100 * 10 ** 18
        );
        _;
    }

    function testUserParticipationInPurchasingSuccessfully()
        public
        getTheLastestMarketAndCreateStall
        registerForStall
        participationInPurchasing
    {
        assertEq(
            Market(lastMarketAddr).getStall().totalTokensSold,
            100 * 10 ** 18
        );
    }

    /*/////////////////////////////////////////////////////////////
                        WITHDRAW STALL TOKEN   
    /////////////////////////////////////////////////////////////*/
    modifier vestingParamsSet() {
        vm.prank(config.defaultAccount);
        Market(lastMarketAddr).setVestingParams(
            [
                block.timestamp + 300,
                block.timestamp + 400,
                block.timestamp + 500
            ],
            [uint256(2000), uint256(3000), uint256(5000)],
            10000
        );
        _;
    }

    function testUserCanWithdrawStallTokensSuccessfully()
        public
        getTheLastestMarketAndCreateStall
        vestingParamsSet
        registerForStall
        participationInPurchasing
    {
        vm.startPrank(project_party);
        ppToken.approve(lastMarketAddr, 3000 * 10 ** 18);
        Market(lastMarketAddr).stallerOwnerDepositStallToken();
        vm.stopPrank();

        uint256[] memory portionIndexes;
        portionIndexes = new uint256[](1);
        portionIndexes[0] = 0;

        vm.warp(block.timestamp + 310);
        vm.roll(block.number + 3);
        vm.prank(user_Alice);
        Market(lastMarketAddr).userWithdrawStallTokens(portionIndexes);
        assertEq(ppToken.balanceOf(user_Alice), 20 * 10 ** 18);
    }

    /*/////////////////////////////////////////////////////////////
            TALL OWNER WITHDRAW YIELD AND REMAINING TOKEN  
    /////////////////////////////////////////////////////////////*/
    function testStallOwnerCanWithdrawYieldSuccessfully()
        public
        getTheLastestMarketAndCreateStall
        vestingParamsSet
        registerForStall
        participationInPurchasing
    {
        vm.startPrank(project_party);
        ppToken.approve(lastMarketAddr, 3000 * 10 ** 18);
        Market(lastMarketAddr).stallerOwnerDepositStallToken();
        vm.stopPrank();

        vm.warp(block.timestamp + 210);
        vm.roll(block.number + 3);

        vm.prank(project_party);
        Market(lastMarketAddr).stallerOwnerWithdrawYield();
        assertEq(project_party.balance, 10 ether);
    }

    function testStallOwnerCanWithdrawRemainingStallTokensSuccessfully()
        public
        getTheLastestMarketAndCreateStall
        vestingParamsSet
        registerForStall
        participationInPurchasing
    {
        vm.startPrank(project_party);
        ppToken.approve(lastMarketAddr, 3000 * 10 ** 18);
        Market(lastMarketAddr).stallerOwnerDepositStallToken();
        vm.stopPrank();

        vm.warp(block.timestamp + 210);
        vm.roll(block.number + 3);

        vm.prank(project_party);
        Market(lastMarketAddr).stallerOwnerWithdrawTheRemainingStallTokens();
        assertEq(ppToken.balanceOf(project_party), 2900 * 10 ** 18);
    }
}
