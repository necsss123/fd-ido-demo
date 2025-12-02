// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {MarketsCreater} from "./launch_pad/MarketsCreater.sol";
import "./libCal.sol";

contract GasBadLpTokenStakeV1 is
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
    function setMarketThatUserCanParticipate(address _user) external {
        require(
            s_marketsCreater.queryMarketIsExist(msg.sender),
            "The market is not exist."
        );

        UserInfo storage userInfo = s_userInfo[_user];
        userInfo.markets.push(msg.sender);
    }

    function setPoolStatus(address _lpToken, bool _status) external onlyOwner {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        require(poolInfo.isLocked != _status, "Repeat setting");
        poolInfo.isLocked = _status;
        if (_status) {
            poolInfo.lockTime = block.timestamp;
        }

        emit PoolStatusChange(_lpToken, _status);
    }

    function setPoolRewardPerSec(
        address _lpToken,
        uint256 _newValue
    ) external onlyOwner {
        PoolInfo storage poolInfo = s_poolInfo[_lpToken];
        require(poolInfo.stakeLpToken != address(0), "The pool doesn't exist");
        require(_newValue >= 0, "Invalid value");
        require(poolInfo.rewardPerSec != _newValue, "Repeat setting");
        poolInfo.rewardPerSec = _newValue;

        emit PoolRewardPerSecChange(_lpToken, _newValue);
    }

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

        emit UserDeposit(_lpToken, msg.sender, _amount);
    }

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

        emit UserWithdraw(_lpToken, msg.sender, actualWithdrawAmount);
    }

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

        emit UserClaimRewards(_lpToken, msg.sender, _amount);
    }

    /* ------------------------------------------------------
                            Public
    ------------------------------------------------------ */
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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /* ------------------------------------------------------
                            Private
    ------------------------------------------------------ */
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

        emit PoolCreated(_lpToken, block.timestamp);
    }

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

    function getUserInfo(
        address _account
    ) external view returns (UserInfo memory) {
        return s_userInfo[_account];
    }

    function getUserStakeRecord(
        address _lpToken,
        address _account
    ) external view returns (bool) {
        return s_userStakeRecord[_lpToken][_account];
    }

    function getTotalAmountOfRewardsDistributed()
        external
        view
        returns (uint256)
    {
        return s_totalAmountOfRewardsDistributed;
    }

    function getRewardToken() external view returns (address) {
        return s_minecraft;
    }

    function getPoolNum() external view returns (uint256) {
        return s_poolArr.length;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
