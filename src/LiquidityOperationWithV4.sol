// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPositionManager} from "@v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@v4-core/src/interfaces/IPoolManager.sol";
import "@v4-core/src/types/PoolKey.sol";
import "@v4-core/src/types/PoolId.sol";
import {IERC20Minimal} from "@v4-core/src/interfaces/external/IERC20Minimal.sol";
import {LiquidityAmounts} from "@v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "@v4-periphery/src/libraries/Actions.sol";
import {IStateView} from "@v4-periphery/src/interfaces/IStateView.sol";
import {TickMath} from "@v4-core/src/libraries/TickMath.sol";
// import {IPermit2} from "@v4-periphery/permit2/src/interfaces/IPermit2.sol";
import "@v4-periphery/src/interfaces/IPermit2Forwarder.sol";
import "./Constants.sol";

contract LiquidityOperationWithV4 {
    IPoolManager public immutable i_poolManager;
    IPositionManager public immutable i_positionManager;
    IStateView public immutable i_stateView;

    Currency public immutable i_minecraft;

    int24 constant TICK_SPACING = 10;

    mapping(PoolId pool => mapping(address user => mapping(int24 lowerTick => mapping(int24 upperTick => uint256 tokenId))))
        public queryTokenId;

    mapping(uint256 tokenId => Currency currency) public queryPool;

    struct Permit2Data {
        IAllowanceTransfer.PermitBatch permit;
        bytes signature;
    }

    constructor(
        address _poolManager,
        address _positionManager,
        address _minecraft,
        address _stateView
    ) {
        i_poolManager = IPoolManager(_poolManager);
        i_positionManager = IPositionManager(_positionManager);
        i_minecraft = Currency.wrap(_minecraft);
        i_stateView = IStateView(_stateView);

        // IERC20Minimal(_minecraft).approve(PERMIT2, type(uint256).max);

        // IPermit2(PERMIT2).approve(
        //     _minecraft,
        //     address(i_positionManager),
        //     type(uint160).max,
        //     type(uint48).max
        // );
    }

    function increaseLiquidity(
        Currency _currency,
        uint256 _minecraftAmount,
        uint256 _currencyAmount,
        int24 _lowerTick,
        int24 _upperTick,
        uint24 _fee,
        Permit2Data calldata batchPermitCurrency
    ) external payable returns (uint256) {
        IPermit2Forwarder(PERMIT2).permitBatch(
            msg.sender,
            batchPermitCurrency.permit,
            batchPermitCurrency.signature
        );

        int24 actualLowerTick = (_lowerTick / TICK_SPACING) * TICK_SPACING;
        int24 actualUpperTick = (_upperTick / TICK_SPACING) * TICK_SPACING;
        uint160 sqrtLowerPrice = TickMath.getSqrtPriceAtTick(actualLowerTick);
        uint160 sqrtUpperPrice = TickMath.getSqrtPriceAtTick(actualUpperTick);

        Currency currency0 = i_minecraft < _currency ? i_minecraft : _currency;
        Currency currency1 = i_minecraft < _currency ? _currency : i_minecraft;

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: _fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolId id = PoolIdLibrary.toId(key);

        (uint160 sqrtPriceX96, , , ) = i_stateView.getSlot0(id);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtLowerPrice,
            sqrtUpperPrice,
            _minecraftAmount,
            _currencyAmount
        );

        uint256 tokenId = queryTokenId[id][msg.sender][actualLowerTick][
            actualUpperTick
        ];

        if (tokenId == 0) {
            // IERC20Minimal(Currency.unwrap(_currency)).approve(
            //     PERMIT2,
            //     type(uint256).max
            // );

            // IPermit2(PERMIT2).approve(
            //     Currency.unwrap(_currency),
            //     address(i_positionManager),
            //     type(uint160).max,
            //     type(uint48).max
            // );

            // IPermit2(PERMIT2).transferFrom(
            //     msg.sender,
            //     address(this),
            //     uint160(_currencyAmount),
            //     Currency.unwrap(_currency)
            // );

            // IPermit2(PERMIT2).transferFrom(
            //     msg.sender,
            //     address(this),
            //     uint160(_minecraftAmount),
            //     Currency.unwrap(i_minecraft)
            // );
            uint256 newTokenId = _mint(
                key,
                currency0,
                currency1,
                actualLowerTick,
                actualUpperTick,
                liquidity
            );

            queryTokenId[id][msg.sender][actualLowerTick][
                actualUpperTick
            ] = newTokenId;

            queryPool[newTokenId] = _currency;

            return newTokenId;
        } else {
            // IPermit2(PERMIT2).transferFrom(
            //     msg.sender,
            //     address(this),
            //     uint160(_currencyAmount),
            //     Currency.unwrap(_currency)
            // );

            // IPermit2(PERMIT2).transferFrom(
            //     msg.sender,
            //     address(this),
            //     uint160(_minecraftAmount),
            //     Currency.unwrap(i_minecraft)
            // );
            _increase(
                tokenId,
                liquidity,
                currency0,
                currency1,
                uint128(currency0.balanceOf(address(this))),
                uint128(currency1.balanceOf(address(this)))
            );
        }

        return tokenId;
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint256 liquidity
    ) external payable {
        Currency currency = queryPool[tokenId];

        Currency currency0 = i_minecraft < currency ? i_minecraft : currency;
        Currency currency1 = i_minecraft < currency ? currency : i_minecraft;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            tokenId,
            liquidity,
            // amount0Min
            1,
            // amount1Min
            1,
            // hook data
            ""
        );

        params[1] = abi.encode(
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            msg.sender
        );

        i_positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp
        );
    }

    function burn(uint256 tokenId) external {
        Currency currency = queryPool[tokenId];

        Currency currency0 = i_minecraft < currency ? i_minecraft : currency;
        Currency currency1 = i_minecraft < currency ? currency : i_minecraft;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.BURN_POSITION),
            uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);

        // BURN_POSITION params
        params[0] = abi.encode(
            tokenId,
            // amount0Min
            1,
            // amount1Min
            1,
            // hook data
            ""
        );

        // TAKE_PAIR params
        // currency 0, currency 1, recipient
        params[1] = abi.encode(
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            address(this)
        );

        i_positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp
        );
    }

    function _mint(
        PoolKey memory key,
        Currency currency0,
        Currency currency1,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    ) internal returns (uint256 tokenId) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);

        // MINT_POSITION params
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            // amount0Max
            type(uint128).max,
            // amount1Max
            type(uint128).max,
            // owner
            msg.sender,
            // hook data
            ""
        );

        address currency0Addr = Currency.unwrap(currency0);
        address currency1Addr = Currency.unwrap(currency1);
        // SETTLE_PAIR params
        // currency 0 and 1
        params[1] = abi.encode(currency0Addr, currency1Addr);

        // SWEEP params
        // currency, address to
        params[2] = abi.encode(currency0Addr, msg.sender);
        params[3] = abi.encode(currency1Addr, msg.sender);

        tokenId = i_positionManager.nextTokenId();

        i_positionManager.modifyLiquidities{value: msg.value}(
            abi.encode(actions, params),
            block.timestamp
        );
    }

    function _increase(
        uint256 tokenId,
        uint256 liquidity,
        Currency currency0,
        Currency currency1,
        uint128 amount0Max,
        uint128 amount1Max
    ) internal {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](5);

        // INCREASE_LIQUIDITY params
        params[0] = abi.encode(
            tokenId,
            liquidity,
            amount0Max,
            amount1Max,
            // hook data
            ""
        );

        // CLOSE_CURRENCY params
        // currency 0
        params[1] = abi.encode(currency0, currency1);

        // CLOSE_CURRENCY params
        // currency 1
        params[2] = abi.encode(currency1);

        // SWEEP params
        // currency, address to
        params[3] = abi.encode(currency0, msg.sender);
        params[4] = abi.encode(currency1, msg.sender);

        i_positionManager.modifyLiquidities{value: msg.value}(
            abi.encode(actions, params),
            block.timestamp
        );
    }
}
