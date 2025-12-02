// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {MarketsCreater} from "./launch_pad/MarketsCreater.sol";
import "./libCal.sol";

/* ----------------------------  Unit Token Accumulation Algorithm  ---------------------------------- 

    假设池子初始默认每秒奖励token数量为1
    用户A --- Alice
    用户B --- Bob
                                                                池子每秒奖励修改为2
                                                                      🔽

    时间轴       0s        1s         2s         3s         4s         5s         6s         7s         8s
    
                |__________|__________|__________|__________|__________|__________|__________|__________|_____ ......

   用户操作     A +1       B +1                  A +2       B +1                  A -1                  B +4

用户A池子中lp数量  1          1                    3          3                     2                     2

用户B池子中lp数量  0          1                    1          2                     2                     6

  池子中lp总量    1          2                    4          5                     4                     8

单位lp累加奖励    0         0+1/1                1+2/2      2+1/4    2.25+1/5    2.45+2/5            2.85 + 4/4 

某用户2次操作间隔产生的待领取奖励
               A 0         B 0               A (2-0)*1   B (2.25-1)*1        A (2.85-2)*3          B (3.85-2.25)*2

公式说明：
单位lp累加奖励         上一个用户操作时的单位lp累加奖励 + 上一个用户操作到当前用户操作之间池子产生的总奖励 / 池子中的lp数量
某用户2次操作间隔产生的待领取奖励        (当前操作最新的单位lp累加奖励 - 上一次操作时的单位lp累加奖励) * 用户在池子中的lp数量
   
    --------------------------------------------------------------------------------------------- */

/**
 * @title LpTokenStakeV1
 * @author necsss
 * @notice LpToken Staking Contract V1, implementing a reward accumulation algorithm based on unit time/unit LP.
 * @dev This is an upgradeable contract (UUPS), implementing Ownable and ReentrancyGuardTransient.
 * @custom:storage-location erc1967
 */
contract LpTokenStakeV1 is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient
{
    /* =======================================================
                        Type Declarations
    ======================================================= */
    using SafeERC20 for IERC20;

    struct Asset {
        address stakeLpToken;
        uint256 amount;
        uint256 rewardsToBeClaimed; // 用户待领取奖励
        uint256 rewardHadBeenClaimed; // 用户已领取奖励
        uint256 lastUnitCumulativeRewards;
    }

    struct UserInfo {
        Asset[] userAssetArr;
        address[] markets; // 记录用户参与的market售卖
    }

    struct PoolInfo {
        address stakeLpToken;
        uint256 totalDepositAmount;
        uint256 rewardPerSec;
        uint256 unitCumulativeRewards;
        uint256 createTime;
        uint256 lastUpdateTime;
        uint256 lockTime;
        bool isLocked; // 锁定状态不影响池子现有用户提取lp和reward，但影响deposit
    }

    /* =======================================================
                        State Variables
    ======================================================= */
    uint256 public constant DEFAULT_POOL_REWARD_PER_SECOND = 1 * 10 ** 18;

    MarketsCreater private s_marketsCreater;

    uint256 private s_totalAmountOfRewardsDistributed;

    address private s_minecraft; // reward token

    mapping(address lpToken => PoolInfo poolInfo) private s_poolInfo;

    mapping(address user => UserInfo userInfo) private s_userInfo;

    mapping(address lpToken => mapping(address user => bool isParticipateIn))
        private s_userStakeRecord;

    address[] s_poolArr; // 只在新建pool时更新

    /* =======================================================
                            Events
    ======================================================= */
    event PoolCreated(address indexed lpToken, uint256 indexed createTime);

    event UserDeposit(
        address indexed lpToken,
        address indexed user,
        uint256 amount
    );

    event UserWithdraw(
        address indexed lpToken,
        address indexed user,
        uint256 amount
    );

    event UserClaimRewards(
        address indexed lpToken,
        address indexed user,
        uint256 amount
    );

    event PoolStatusChange(address indexed lpToken, bool indexed status);

    event PoolRewardPerSecChange(
        address indexed lpToken,
        uint256 indexed newValue
    );

    /* =======================================================
                            Errors
    ======================================================= */
    error LpTokenStakeV1__UserIsNotInThePool();

    error LpTokenStakeV1__NotSufficientRewards();

    /* =======================================================
                            Functions
    ======================================================= */

    /* ------------------------------------------------------
                    Initializer/Constructor
    ------------------------------------------------------ */
    /**
     * @notice Initializes the contract, setting the reward token and MarketsCreater contract addresses.
     * @param _minecraft The address of the Reward Token.
     * @param _marketsCreater The address of the MarketsCreater contract.
     */
    function initialize(
        address _minecraft,
        address _marketsCreater
    ) public initializer {
        __Ownable_init(msg.sender);
        s_minecraft = _minecraft;
        s_marketsCreater = MarketsCreater(_marketsCreater);
    }

    /* ------------------------------------------------------
                        External
    ------------------------------------------------------ */
    /**
     * @notice Sets the market address that a user is allowed to participate in. Only callable by existing markets registered in MarketsCreater.
     * @param _user The address of the user to grant market participation access to.
     */
    function setMarketThatUserCanParticipate(address _user) external {
        require(
            s_marketsCreater.queryMarketIsExist(msg.sender),
            "The market is not exist."
        );

        UserInfo storage userInfo = s_userInfo[_user];
        userInfo.markets.push(msg.sender);
    }

    /**
     * @notice Locks or unlocks the LP pool. A locked status prevents new deposits but does not affect withdrawals or reward claiming for existing stakers.
     * @dev Only the contract owner can call this.
     * @param _lpToken The LP token address.
     * @param _status The desired lock status (true for locked, false for unlocked).
     */
    function setPoolStatus(address _lpToken, bool _status) external onlyOwner {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        require(poolInfo.isLocked != _status, "Repeat setting");
        poolInfo.isLocked = _status;
        if (_status) {
            poolInfo.lockTime = block.timestamp;
        }

        assembly {
            log3(
                0x00,
                0x00,
                // keccak256("PoolStatusChange(address,bool)")
                0x7386f399e3e8e66fe448d76be58d851869b03f2012498394e76c8e1676b7fe7e,
                _lpToken,
                _status
            )
        }
    }

    /**
     * @notice Sets the reward amount per second for the LP pool.
     * @dev Only the contract owner can call this.
     * @param _lpToken The LP token address.
     * @param _newValue The new reward amount per second.
     */
    function setPoolRewardPerSec(
        address _lpToken,
        uint256 _newValue
    ) external onlyOwner {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        require(_newValue >= 0, "Invalid value");
        require(poolInfo.rewardPerSec != _newValue, "Repeat setting");
        poolInfo.rewardPerSec = _newValue;

        assembly {
            log3(
                0x00,
                0x00,
                // keccak256("PoolRewardPerSecChange(address,uint256)")
                0xb69a3e5d06ba8d19ca8950078fbd24dfc94526132982ddb40686c7b75a534f84,
                _lpToken,
                _newValue
            )
        }
    }

    /**
     * @notice Allows a user to deposit LP tokens into the specified pool.
     * @dev If the pool does not exist, it will be created automatically. Cannot deposit if the pool is locked.
     * @param _lpToken The address of the LP token to stake.
     * @param _amount The amount to deposit.
     */
    function userDepositLpToken(
        address _lpToken,
        uint256 _amount
    ) external nonReentrant {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        UserInfo storage userInfo = s_userInfo[msg.sender];

        if (poolInfo.stakeLpToken == address(0)) {
            _createPool(_lpToken);
            poolInfo = s_poolInfo[_lpToken];
        }

        require(!poolInfo.isLocked, "Sorry, the pool is curently inactive.");

        (
            uint256 newLastUpdateTime,
            uint256 newUnitCumulativeRewards
        ) = _updatePoolInfo(poolInfo);
        poolInfo.unitCumulativeRewards = newUnitCumulativeRewards;
        poolInfo.lastUpdateTime = newLastUpdateTime;
        poolInfo.totalDepositAmount += _amount;
        bool userIsParticipated = s_userStakeRecord[poolInfo.stakeLpToken][
            msg.sender
        ];

        if (!userIsParticipated) {
            userInfo.userAssetArr.push(
                Asset({
                    stakeLpToken: _lpToken,
                    amount: _amount,
                    rewardsToBeClaimed: 0,
                    rewardHadBeenClaimed: 0,
                    lastUnitCumulativeRewards: poolInfo.unitCumulativeRewards
                })
            );
            s_userStakeRecord[poolInfo.stakeLpToken][msg.sender] = true;
        } else {
            Asset[] storage assetArr = userInfo.userAssetArr;
            uint256 assetNum = assetArr.length;

            for (uint256 i = 0; i < assetNum; i++) {
                if (assetArr[i].stakeLpToken == _lpToken) {
                    uint256 rewardsGeneratedSinceTheLastOperation = Cal
                        .calRewardsGeneratedSinceTheLastOperation(
                            poolInfo.unitCumulativeRewards,
                            assetArr[i].lastUnitCumulativeRewards,
                            assetArr[i].amount
                        );
                    assetArr[i]
                        .rewardsToBeClaimed += rewardsGeneratedSinceTheLastOperation;
                    assetArr[i].lastUnitCumulativeRewards = poolInfo
                        .unitCumulativeRewards;
                    assetArr[i].amount += _amount;
                    break;
                }
            }
        }

        IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), _amount);

        assembly {
            mstore(0x00, _amount)
            log3(
                0x00,
                0x20,
                // keccak256("UserDeposit(address,address,uint256)")
                0x3bc57f469ad6d10d7723ea226cd22bd2b9e527def2b529f6ab44645a16689582,
                _lpToken,
                caller()
            )
        }
    }

    /**
     * @notice Allows a user to withdraw LP tokens and all pending rewards from the specified pool.
     * @dev If the withdrawal amount equals the staked amount, the user is removed from the pool.
     * @param _lpToken The LP token address.
     * @param _amount The amount of LP tokens to withdraw.
     */
    function userWithdrawLpToken(
        address _lpToken,
        uint256 _amount
    ) external nonReentrant {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        bool userIsParticipated = s_userStakeRecord[poolInfo.stakeLpToken][
            msg.sender
        ];
        if (!userIsParticipated) revert LpTokenStakeV1__UserIsNotInThePool();

        UserInfo storage userInfo = s_userInfo[msg.sender];
        Asset[] storage assetArr = userInfo.userAssetArr;
        uint256 assetNum = assetArr.length;
        uint256 actualWithdrawAmount;

        for (uint256 i = 0; i < assetNum; i++) {
            if (assetArr[i].stakeLpToken == _lpToken) {
                uint256 userDepositAmount = assetArr[i].amount;

                (
                    uint256 newLastUpdateTime,
                    uint256 newUnitCumulativeRewards
                ) = _updatePoolInfo(poolInfo);
                poolInfo.unitCumulativeRewards = newUnitCumulativeRewards;
                poolInfo.lastUpdateTime = newLastUpdateTime;

                uint256 rewardsGeneratedSinceTheLastOperation = Cal
                    .calRewardsGeneratedSinceTheLastOperation(
                        poolInfo.unitCumulativeRewards,
                        assetArr[i].lastUnitCumulativeRewards,
                        assetArr[i].amount
                    );
                assetArr[i]
                    .rewardsToBeClaimed += rewardsGeneratedSinceTheLastOperation;

                // 部分取出
                if (userDepositAmount > _amount) {
                    assetArr[i].lastUnitCumulativeRewards = poolInfo
                        .unitCumulativeRewards; // 全部取出则不需要更新这项，省点儿gas
                    poolInfo.totalDepositAmount -= _amount;
                    assetArr[i].amount -= _amount;
                    IERC20(_lpToken).safeTransfer(msg.sender, _amount);
                    actualWithdrawAmount = _amount;
                    // 全部取出
                } else {
                    poolInfo.totalDepositAmount -= userDepositAmount;
                    // assetArr[i].amount = 0;   也不需要更新，省点儿gas
                    s_totalAmountOfRewardsDistributed += assetArr[i]
                        .rewardsToBeClaimed;
                    actualWithdrawAmount = userDepositAmount;

                    IERC20(_lpToken).safeTransfer(
                        msg.sender,
                        userDepositAmount
                    );
                    IERC20(s_minecraft).safeTransfer(
                        msg.sender,
                        assetArr[i].rewardsToBeClaimed
                    );
                    s_userStakeRecord[_lpToken][msg.sender] = false;
                    // 删除数组中对应的Asset
                    uint256 last = assetNum - 1;
                    if (i != last) {
                        assetArr[i] = assetArr[assetNum - 1];
                    }
                    assetArr.pop();
                }

                break;
            }
        }

        assembly {
            mstore(0x00, actualWithdrawAmount)
            log3(
                0x00,
                0x20,
                // keccak256("UserWithdraw(address,address,uint256)")
                0x6985a6dd52aeb8194df40b7af2f362f362440affc39c1314649abc28dbf6b628,
                _lpToken,
                caller()
            )
        }
    }

    /**
     * @notice Allows a user to claim reward tokens from the specified pool.
     * @dev Calculates the latest pending rewards before claiming, then deducts and transfers the amount.
     * @param _lpToken The corresponding LP token address.
     * @param _amount The amount of rewards to claim.
     */
    function userClaimRewards(
        address _lpToken,
        uint256 _amount
    ) external nonReentrant {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        bool userIsParticipated = s_userStakeRecord[poolInfo.stakeLpToken][
            msg.sender
        ];
        if (!userIsParticipated) revert LpTokenStakeV1__UserIsNotInThePool();

        (
            uint256 lastRewardsToBeClaimed,
            uint256 newUnitCumulativeRewards
        ) = getUserRewardsToBeClaimed(_lpToken, msg.sender);

        UserInfo storage userInfo = s_userInfo[msg.sender];
        Asset[] storage assetArr = userInfo.userAssetArr;
        uint256 assetNum = assetArr.length;

        for (uint256 i = 0; i < assetNum; i++) {
            if (assetArr[i].stakeLpToken == _lpToken) {
                assetArr[i].rewardsToBeClaimed = lastRewardsToBeClaimed;
                assetArr[i]
                    .lastUnitCumulativeRewards = newUnitCumulativeRewards;
                if (assetArr[i].rewardsToBeClaimed < _amount)
                    revert LpTokenStakeV1__NotSufficientRewards();
                assetArr[i].rewardsToBeClaimed -= _amount;
                assetArr[i].rewardHadBeenClaimed += _amount;
                s_totalAmountOfRewardsDistributed += _amount;
                IERC20(s_minecraft).safeTransfer(msg.sender, _amount);
                break;
            }
        }

        assembly {
            mstore(0x00, _amount)
            log3(
                0x00,
                0x20,
                // keccak256("UserClaimRewards(address,address,uint256)")
                0x149e4c17cd2c0ed2d4634ef7e00828d0873ecfd6a043c848c0fc1ab0bf7d6dd3,
                _lpToken,
                caller()
            )
        }
    }

    /* ------------------------------------------------------
                            Public
    ------------------------------------------------------ */

    /**
     * @notice Calculates the user's current total pending rewards in a specific pool (including rewards accumulated since the last operation).
     * @param _lpToken The LP token address.
     * @param _user The user's address.
     * @return lastRewards The user's latest total pending rewards.
     * @return newUnitCumulativeRewards The pool's latest unit cumulative reward value after calculating the reward.
     */
    function getUserRewardsToBeClaimed(
        address _lpToken,
        address _user
    )
        public
        view
        returns (uint256 lastRewards, uint256 newUnitCumulativeRewards)
    {
        PoolInfo memory poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        bool userIsParticipated = s_userStakeRecord[poolInfo.stakeLpToken][
            _user
        ];
        if (!userIsParticipated) revert LpTokenStakeV1__UserIsNotInThePool();

        (, newUnitCumulativeRewards) = _updatePoolInfo(poolInfo);

        UserInfo memory userInfo = s_userInfo[_user];
        Asset[] memory assetArr = userInfo.userAssetArr;
        uint256 assetNum = assetArr.length;
        for (uint256 i = 0; i < assetNum; i++) {
            if (assetArr[i].stakeLpToken == _lpToken) {
                uint256 rewardsGeneratedSinceTheLastOperation = Cal
                    .calRewardsGeneratedSinceTheLastOperation(
                        newUnitCumulativeRewards,
                        assetArr[i].lastUnitCumulativeRewards,
                        assetArr[i].amount
                    );
                lastRewards =
                    assetArr[i].rewardsToBeClaimed +
                    rewardsGeneratedSinceTheLastOperation;
                break;
            }
        }
        return (lastRewards, newUnitCumulativeRewards);
    }

    /* ------------------------------------------------------
                            Internal
    ------------------------------------------------------ */
    /**
     * @notice Authorization function required for UUPS upgradeable contracts.
     * @dev Only the contract owner can authorize an upgrade.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /* ------------------------------------------------------
                            Private
    ------------------------------------------------------ */
    /**
     * @notice Creates a new LP staking pool.
     * @dev Only called when a user makes the first Deposit.
     * @param _lpToken The address of the LP token corresponding to the pool to be created.
     */
    function _createPool(address _lpToken) private {
        s_poolArr.push(_lpToken);

        s_poolInfo[_lpToken] = PoolInfo({
            stakeLpToken: _lpToken,
            totalDepositAmount: 0,
            rewardPerSec: DEFAULT_POOL_REWARD_PER_SECOND,
            unitCumulativeRewards: 0,
            createTime: block.timestamp,
            lockTime: 0,
            lastUpdateTime: block.timestamp,
            isLocked: false
        });

        assembly {
            log3(
                0x00,
                0x00,
                // keccak256("PoolCreated(address,uint256)")
                0x641e49906554552c8c33d7e09e02d1270590f405bc1da0c7b99a9c2808abdd05,
                _lpToken,
                timestamp()
            )
        }
    }

    /**
     * @notice Updates the unit cumulative reward value (`unitCumulativeRewards`) for the specified pool.
     * @dev If the pool's total staked amount (`totalDepositAmount`) is 0, the unit cumulative reward value does not increase.
     * @param _poolInfo The current information of the pool.
     * @return newLastUpdateTime The new `lastUpdateTime` (typically the current block timestamp).
     * @return newUnitCumulativeRewards The new unit cumulative reward value.
     */
    function _updatePoolInfo(
        PoolInfo memory _poolInfo
    )
        private
        view
        returns (uint256 newLastUpdateTime, uint256 newUnitCumulativeRewards)
    {
        require(block.timestamp >= _poolInfo.lastUpdateTime, "invalid time");
        require(_poolInfo.totalDepositAmount >= 0, "impossible amount");
        uint256 duration = block.timestamp - _poolInfo.lastUpdateTime;

        /*
        duration 等于 0 有两种情况：
        1. 创建pool的时候
        2. 在同一时刻，比如在第3秒，A用户操作完，B用户也在第3秒进行操作
        */
        if (duration != 0) {
            uint256 totalRewardsInDuration = _poolInfo.rewardPerSec * duration;
            newUnitCumulativeRewards = Cal.calNewUnitCumulativeRewards(
                _poolInfo.unitCumulativeRewards,
                totalRewardsInDuration,
                _poolInfo.totalDepositAmount
            );
            return (block.timestamp, newUnitCumulativeRewards);
        }
        return (_poolInfo.lastUpdateTime, _poolInfo.unitCumulativeRewards);
    }

    /* ------------------------------------------------------
                            Getter
    ------------------------------------------------------ */
    /**
     * @notice Retrieves the latest information for an LP pool. If time has elapsed, the unit cumulative reward is updated first.
     * @param _lpToken The LP token address.
     * @return PoolInfo The pool struct containing the latest unit cumulative reward information.
     */
    function getPoolInfo(
        address _lpToken
    ) external view returns (PoolInfo memory) {
        PoolInfo memory poolInfo = s_poolInfo[_lpToken];
        if (block.timestamp > poolInfo.lastUpdateTime) {
            (
                uint256 newLastUpdateTime,
                uint256 newUnitCumulativeRewards
            ) = _updatePoolInfo(poolInfo);
            poolInfo.lastUpdateTime = newLastUpdateTime;
            poolInfo.unitCumulativeRewards = newUnitCumulativeRewards;
        }

        return poolInfo;
    }

    /**
     * @notice Retrieves a user's staking information.
     * @param _account The user's address.
     * @return UserInfo The user's staking information struct.
     */
    function getUserInfo(
        address _account
    ) external view returns (UserInfo memory) {
        return s_userInfo[_account];
    }

    /**
     * @notice Queries whether a user has staked in a specific LP pool.
     * @param _lpToken The LP token address.
     * @param _account The user's address.
     * @return bool Whether the user is participating in staking.
     */
    function getUserStakeRecord(
        address _lpToken,
        address _account
    ) external view returns (bool) {
        return s_userStakeRecord[_lpToken][_account];
    }

    /**
     * @notice Retrieves the total amount of reward tokens distributed by the contract.
     * @return uint256 The total distributed amount.
     */
    function getTotalAmountOfRewardsDistributed()
        external
        view
        returns (uint256)
    {
        return s_totalAmountOfRewardsDistributed;
    }

    /**
     * @notice Retrieves the address of the reward token.
     * @return address The reward token address.
     */
    function getRewardToken() external view returns (address) {
        return s_minecraft;
    }

    /**
     * @notice Retrieves the number of created LP pools.
     * @return uint256 The number of LP pools.
     */
    function getPoolNum() external view returns (uint256) {
        return s_poolArr.length;
    }

    /**
     * @notice Returns the contract version number.
     * @return uint256 The version number (1).
     */
    function version() external pure returns (uint256) {
        return 1;
    }
}
