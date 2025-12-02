/*
* Verification of GasBadLpTokenStakeV1
*/

using GasBadLpTokenStakeV1 as gasBadLpTokenStakeV1;
using LpTokenStakeV1 as lpTokenStakeV1;
using Minecraft as rewardToken;

methods {

    function getTotalAmountOfRewardsDistributed() external returns uint256 envfree;
    function getPoolNum() external returns uint256 envfree;
    function getUserStakeRecord(address, address) external returns bool envfree;
    function getUserRewardsToBeClaimed(address, address) public returns (uint256, uint256);
    function GasBadLpTokenStakeV1.getPoolInfo(address) external returns GasBadLpTokenStakeV1.PoolInfo;
    function LpTokenStakeV1.getPoolInfo(address) external returns LpTokenStakeV1.PoolInfo;

    function _.proxiableUUID() external => DISPATCHER(true);
    function _.transfer(address,uint256) external => DISPATCHER(true);
    function _.transferFrom(address,address,uint256) external => DISPATCHER(true);
}

rule calling_any_function_should_result_in_each_contract_having_the_same_state(method f, method f2) {
    
    require(f.selector == f2.selector);

    env e;
    calldataarg args;
    address lpToken;
    address user;

    (uint256 gasBadRewards, uint256 gasBadNewUnit) = gasBadLpTokenStakeV1.getUserRewardsToBeClaimed(e,lpToken,user);
    (uint256 lpRewards, uint256 lpNewUnit) = lpTokenStakeV1.getUserRewardsToBeClaimed(e,lpToken,user);

    require(gasBadLpTokenStakeV1.getTotalAmountOfRewardsDistributed(e) == lpTokenStakeV1.getTotalAmountOfRewardsDistributed(e));
    require(gasBadLpTokenStakeV1.getPoolNum(e) == lpTokenStakeV1.getPoolNum(e));
    require(gasBadRewards == lpRewards);
    require(gasBadNewUnit == lpNewUnit);
    require(gasBadLpTokenStakeV1.getUserStakeRecord(e,lpToken,user) == lpTokenStakeV1.getUserStakeRecord(e,lpToken,user));
    require(gasBadLpTokenStakeV1.getPoolInfo(e,lpToken).unitCumulativeRewards == lpTokenStakeV1.getPoolInfo(e,lpToken).unitCumulativeRewards);


    gasBadLpTokenStakeV1.f(e, args);
    lpTokenStakeV1.f2(e, args);

    assert(gasBadLpTokenStakeV1.getTotalAmountOfRewardsDistributed(e) == lpTokenStakeV1.getTotalAmountOfRewardsDistributed(e));

}