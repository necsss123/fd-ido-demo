// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISubscriber} from "@v4-periphery/src/interfaces/ISubscriber.sol";
import {IPositionManager} from "@v4-periphery/src/interfaces/IPositionManager.sol";
import {BalanceDelta} from "@v4-core/src/types/BalanceDelta.sol";
import {PositionInfo} from "@v4-periphery/src/libraries/PositionInfoLibrary.sol";

contract MinecraftSubscriber is ISubscriber {
    IPositionManager public immutable positionManager;

    constructor(IPositionManager _positionManager) {
        positionManager = _positionManager;
    }

    modifier onlyByPosm() {
        require(msg.sender == address(positionManager), "Unauthorized");
        _;
    }

    function notifySubscribe(uint256, bytes memory) external onlyByPosm {}

    function notifyUnsubscribe(uint256) external onlyByPosm {}

    function notifyModifyLiquidity(
        uint256,
        int256,
        BalanceDelta
    ) external onlyByPosm {}

    function notifyBurn(
        uint256,
        address,
        PositionInfo,
        uint256,
        BalanceDelta
    ) external onlyByPosm {}
}
