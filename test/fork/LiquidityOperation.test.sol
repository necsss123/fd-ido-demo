// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test, console} from "forge-std/Test.sol";
import {TestAssister} from "../TestAssister.sol";
import {TestUtil} from "../TestUtil.sol";
import {IERC20Minimal} from "@v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPositionManager} from "@v4-periphery/src/interfaces/IPositionManager.sol";
import {POSITION_MANAGER, POOL_MANAGER, USDC, WBTC, STATE_VIEW, PERMIT2} from "../../src/Constants.sol";
import {LiquidityOperationWithV4} from "../../src/LiquidityOperationWithV4.sol";
import "@v4-core/src/types/PoolKey.sol";
import "@v4-periphery/permit2/src/interfaces/IPermit2.sol";
// import "@v4-periphery/src/interfaces/IPermit2Forwarder.sol";
import {PermitHash} from "@v4-periphery/permit2/src/libraries/PermitHash.sol";

contract LiquidityOperationTest is Test, TestUtil {
    IERC20Minimal constant usdc = IERC20Minimal(USDC);
    IERC20Minimal constant wbtc = IERC20Minimal(WBTC);

    IPositionManager constant posm = IPositionManager(POSITION_MANAGER);

    LiquidityOperationWithV4 lpOperation;

    int24 constant TICK_SPACING = 10;

    TestAssister testAssister;
    PoolKey key;

    address user;
    uint256 userPrivateKey;

    receive() external payable {}

    function setUp() public {
        testAssister = new TestAssister();
        lpOperation = new LiquidityOperationWithV4(
            POOL_MANAGER,
            POSITION_MANAGER,
            WBTC,
            STATE_VIEW
        );

        (user, userPrivateKey) = makeAddrAndKey("user_Alice");

        deal(USDC, user, 1e6 * 1e6);
        deal(WBTC, user, 10 * 1e8);
        deal(user, 100 * 1e18);

        // deal(USDC, address(lpOperation), 1e6 * 1e6);
        // deal(WBTC, address(lpOperation), 10 * 1e8);

        vm.startPrank(user);

        usdc.approve(PERMIT2, type(uint256).max);
        wbtc.approve(PERMIT2, type(uint256).max);

        IPermit2(PERMIT2).approve(
            USDC,
            address(lpOperation),
            type(uint160).max,
            type(uint48).max
        );

        IPermit2(PERMIT2).approve(
            WBTC,
            address(lpOperation),
            type(uint160).max,
            type(uint48).max
        );

        vm.stopPrank();

        key = PoolKey({
            currency0: Currency.wrap(WBTC),
            currency1: Currency.wrap(USDC),
            fee: 500,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    // forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUM --match-path test/fork/LiquidityOperation.test.sol --match-test test_mint_burn -vvv --via-ir
    function test_mint_burn() public {
        int24 tick = getTick(key.toId());

        int24 tickLower = getTickLower(tick, TICK_SPACING);

        // Mint
        console.log("--- mint ---");

        testAssister.set("WBTC before", wbtc.balanceOf(user));
        testAssister.set("USDC before", usdc.balanceOf(user));

        ISignatureTransfer.TokenPermissions
            memory token0Perm = ISignatureTransfer.TokenPermissions({
                token: WBTC,
                amount: 1 * 1e8
            });

        ISignatureTransfer.TokenPermissions
            memory token1Perm = ISignatureTransfer.TokenPermissions({
                token: USDC,
                amount: 100000 * 1e6
            });

        ISignatureTransfer.TokenPermissions[] memory tokenPermArr;
        tokenPermArr = new ISignatureTransfer.TokenPermissions[](2);
        tokenPermArr[0] = token0Perm;
        tokenPermArr[1] = token1Perm;

        ISignatureTransfer.PermitBatchTransferFrom
            memory permitBatch = ISignatureTransfer.PermitBatchTransferFrom({
                permitted: tokenPermArr,
                nonce: 1,
                deadline: block.timestamp
            });

        bytes32 structHash = PermitHash.hash(permitBatch);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IPermit2(PERMIT2).DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        LiquidityOperationWithV4.AuthData
            memory permitData = LiquidityOperationWithV4.AuthData({
                permit: permitBatch,
                signature: signature
            });

        vm.prank(user);
        uint256 tokenId = lpOperation.increaseLiquidity(
            Currency.wrap(USDC),
            1 * 1e8,
            100000 * 1e6,
            tickLower - 10 * TICK_SPACING,
            tickLower + 10 * TICK_SPACING,
            500,
            permitData
        );

        testAssister.set("WBTC after", wbtc.balanceOf(user));
        testAssister.set("USDC after", usdc.balanceOf(user));

        console.log("liquidity: %e", posm.getPositionLiquidity(tokenId));

        int256 d0 = testAssister.delta("WBTC after", "WBTC before");
        int256 d1 = testAssister.delta("USDC after", "USDC before");
        console.log("WBTC delta: %e", d0);
        console.log("USDC delta: %e", d1);
        // console.log(
        //     "LpOperation WBTC after: %e",
        //     wbtc.balanceOf(address(lpOperation))
        // );
        // console.log(
        //     "LpOperation USDC after: %e",
        //     usdc.balanceOf(address(lpOperation))
        // );
    }
}
