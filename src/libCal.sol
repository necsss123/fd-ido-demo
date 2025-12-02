// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Cal {
    uint256 public constant RAY = 10 ** 27;

    function calNewUnitCumulativeRewards(
        uint256 lastUnitCumulativeRewards,
        uint256 totalAmountOfRewardsInTheDuration,
        uint256 totalAmountStakeInPool
    ) internal pure returns (uint256) {
        if (totalAmountStakeInPool == 0) {
            return 0;
        } else {
            return
                lastUnitCumulativeRewards +
                (totalAmountOfRewardsInTheDuration * RAY) /
                totalAmountStakeInPool;
        }
    }

    function calRewardsGeneratedSinceTheLastOperation(
        uint256 newUnitCumulativeRewards,
        uint256 lastUnitCumulativeRewards,
        uint256 usersAmountInPool
    ) internal pure returns (uint256) {
        return
            ((newUnitCumulativeRewards - lastUnitCumulativeRewards) *
                usersAmountInPool) / RAY;
    }
}
