// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketsCreater} from "./MarketsCreater.sol";
import {LpTokenStakeV1} from "../LpTokenStakeV1.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Market
 * @author necsss
 * @notice The Market contract manages a token stall with registration,
 *         vesting, purchase limits, and profit withdrawal for the stall owner.
 *         Users must first register, then purchase tokens and later withdraw
 *         vested tokens by portions.
 * @dev - The contract is deployed via MarketsCreater and uses its owner as the admin.
 *      - Vesting is handled using three unlock timestamps and percentage allocations.
 *      - Each user can purchase only once, guarded by signature-based authorization.
 *      - The stall owner deposits tokens once and can withdraw profits and remaining
 *        unsold tokens after the sale.
 */
contract Market is ReentrancyGuard {
    /* =======================================================
                        Type Declarations
    ======================================================= */
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    struct Stall {
        address stallToken; // 正在被出售的代币
        address stallOwner; // 项目方(卖家)地址
        uint256 tokenPriceInETH; // 代币的ETH价格
        uint256 amountOfTokensToSell; // 出售的代币数量
        uint256 totalTokensSold; // 已出售的代币总量
        uint256 totalETHRaised; // 筹集的ETH总额
        uint256 stallStart; // 售卖开始时间
        uint256 stallEnd; // 售卖结束时间
        // 购买后vesting相关
        uint256 portionVestingPrecision;
        uint256[3] vestingPortionsUnlockTime;
        uint256[3] vestingPercentPerPortion;
        // 注册相关
        uint256 registrationTimeStart; // 注册开始时间
        uint256 registrationTimeEnd; // 注册结束时间
        uint256 numOfRegistrants; // 注册人数
    }

    struct WithdrawalInfo {
        uint256 amountBought; // 购买数量
        uint256 amountETHPaid; // 支付的ETH总额
        bool[3] isPortionWithdrawn; // 已提取的部分(按比例)
    }

    /* =======================================================
                        State Variables
    ======================================================= */
    MarketsCreater private immutable i_marketsCreater;

    LpTokenStakeV1 private immutable i_lpTokenStake;

    Stall public s_stall;

    mapping(address user => WithdrawalInfo) public s_userToWithdrawl;

    mapping(address user => bool) public s_isRegistered;

    mapping(bytes32 => bool) private s_hasBeenCalled;

    /* =======================================================
                            Events
    ======================================================= */
    event StallCreate(address indexed stallToken, address indexed stallOwner);
    event VestingParamsSet(address indexed stallToken);
    event UserRegistration(address indexed user);
    event StallTokenDeposite(address indexed StallOwner, uint256 indexed time);
    event UserPurchase(address indexed user, uint256 indexed amountToBuy);
    event UserWithdrawl(address indexed user, uint256 indexed amountToWithdraw);
    event StallOwnerWithdrawProfits(
        address indexed stallOwner,
        uint256 indexed amountToWithdraw
    );
    event StallOwnerWithdrawRemainTokens(
        address indexed stallOwner,
        uint256 indexed amountToWithdraw
    );

    /* =======================================================
                            Errors
    ======================================================= */
    error Market__PrecisionMismatch();
    error Market__PortionIndexIsOutOfUnlockRange();
    error Market__ExceedingTheAllowance();
    error Market__TokensHaveBeenWithdrawn();
    error Market__PortionHasNotBeenUnlocked();
    error Market__StallOwnerFailsToWithdrawProfits();

    /* =======================================================
                            Modifiers
    ======================================================= */
    modifier onlyStallOwner() {
        require(
            msg.sender == s_stall.stallOwner,
            "Can only call by stall owner."
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            msg.sender == i_marketsCreater.owner(),
            "Can only call by admin."
        );
        _;
    }

    modifier onlyOnce(bytes32 funcId) {
        require(!s_hasBeenCalled[funcId], "This func can only be called once.");
        _;
    }

    /* =======================================================
                            Functions
    ======================================================= */

    /* ------------------------------------------------------
                            Constructor
    ------------------------------------------------------ */
    /**
     * @notice Initializes the immutable state variables.
     * @dev The constructor expects the MarketsCreater address to be `msg.sender`
     * when the contract is deployed via the factory pattern.
     * @param _stake The address of the LpTokenStakeV1 contract.
     */
    constructor(address _stake) {
        i_lpTokenStake = LpTokenStakeV1(_stake);
        i_marketsCreater = MarketsCreater(msg.sender);
    }

    /* ------------------------------------------------------
                            External
    ------------------------------------------------------ */
    /**
     * @notice Sets the main parameters for the token sale stall.
     * @dev Can only be called once by the Admin.
     * @param _token The token being sold.
     * @param _stallOwner The project owner address.
     * @param _tokenPriceInETH The price of one token in ETH (in $10^{18}$ wei/token).
     * @param _amount The total amount of tokens to sell.
     * @param _stallStart Sale start time.
     * @param _stallEnd Sale end time.
     * @param _registrationTimeStart Registration start time.
     * @param _registrationTimeEnd Registration end time.
     */
    function createStall(
        address _token,
        address _stallOwner,
        uint256 _tokenPriceInETH,
        uint256 _amount,
        uint256 _stallStart,
        uint256 _stallEnd,
        uint256 _registrationTimeStart,
        uint256 _registrationTimeEnd
    ) external onlyAdmin onlyOnce(keccak256("createStall")) {
        require(
            _token != address(0) ||
                _stallOwner != address(0) ||
                _tokenPriceInETH != 0 ||
                _amount != 0 ||
                _registrationTimeStart > block.timestamp ||
                _registrationTimeStart < _registrationTimeEnd ||
                _stallStart > block.timestamp ||
                _stallStart < _stallEnd,
            "Invalid input params"
        );
        require(
            _stallStart > _registrationTimeEnd,
            "Stall start time should be greater than reg end time."
        );

        s_stall.stallToken = _token;
        s_stall.stallOwner = _stallOwner;
        s_stall.tokenPriceInETH = _tokenPriceInETH;
        s_stall.amountOfTokensToSell = _amount;
        s_stall.stallStart = _stallStart;
        s_stall.stallEnd = _stallEnd;
        s_stall.registrationTimeStart = _registrationTimeStart;
        s_stall.registrationTimeEnd = _registrationTimeEnd;

        emit StallCreate(_token, _stallOwner);
    }

    /**
     * @notice Sets the vesting schedule parameters for the tokens purchased in this stall.
     * @dev Must be called after `createStall`. Can only be called once by the Admin.
     * @param _unlockingTimes Array of 3 timestamps for the vesting unlock events.
     * @param _percents Array of 3 percentages corresponding to each portion.
     * @param _portionVestingPrecision The precision used for calculation (e.g., 100 for percentage).
     */
    function setVestingParams(
        uint256[3] memory _unlockingTimes,
        uint256[3] memory _percents,
        uint256 _portionVestingPrecision
    ) external onlyAdmin onlyOnce(keccak256("setVestingParams")) {
        require(
            s_stall.stallToken != address(0),
            "Please call the createStall func first."
        );
        require(
            _unlockingTimes[0] > s_stall.stallEnd,
            "The unlock time should be longer than the stall end time."
        );

        uint256 sum;
        for (uint256 i = 0; i < 3; i++) {
            s_stall.vestingPortionsUnlockTime[i] = _unlockingTimes[i];
            s_stall.vestingPercentPerPortion[i] = _percents[i];
            sum += _percents[i];
        }

        if (sum != _portionVestingPrecision || sum < 100)
            revert Market__PrecisionMismatch();

        s_stall.portionVestingPrecision = _portionVestingPrecision;

        emit VestingParamsSet(s_stall.stallToken);
    }

    /**
     * @notice Allows a user to register for the stall using a signature provided by the Admin.
     * @dev The signature is only given to users who participate in the $LpTokenStakeV1$ staking.
     * @param _signature The signed message from the Admin to verify registration eligibility.
     */
    function registerForStall(bytes memory _signature) external {
        require(
            block.timestamp > s_stall.registrationTimeStart &&
                block.timestamp < s_stall.registrationTimeEnd,
            "Non-registration time."
        );

        require(
            checkRegistrationSignature(_signature, msg.sender),
            "Invalid signature."
        );

        require(!s_isRegistered[msg.sender], "Can not register repeatedly.");

        s_isRegistered[msg.sender] = true;
        s_stall.numOfRegistrants++;
        i_lpTokenStake.setMarketThatUserCanParticipate(msg.sender);

        emit UserRegistration(msg.sender);
    }

    /**
     * @notice Allows the Stall Owner to deposit the tokens to be sold into the contract.
     * @dev Must be called before the sale starts. Can only be called once by the Stall Owner.
     */
    function stallerOwnerDepositStallToken()
        external
        onlyStallOwner
        onlyOnce(keccak256("depositStallToken"))
    {
        IERC20(s_stall.stallToken).safeTransferFrom(
            msg.sender,
            address(this),
            s_stall.amountOfTokensToSell
        );

        emit StallTokenDeposite(msg.sender, block.timestamp);
    }

    /**
     * @notice Allows a registered user to participate in the purchase by sending ETH.
     * @dev The amount of tokens purchased is determined by the ETH sent (`msg.value`) and the `tokenPriceInETH`.
     * @param _signature Admin signature verifying the user's purchase allowance.
     * @param _allowance The maximum allowed purchase amount (signed by the admin).
     */
    function userParticipationInPurchasing(
        bytes memory _signature,
        uint256 _allowance
    ) external payable nonReentrant {
        require(
            block.timestamp > s_stall.stallStart &&
                block.timestamp < s_stall.stallEnd,
            "Not in the sale time."
        );
        require(s_isRegistered[msg.sender], "Not registered for the stall.");
        require(
            s_userToWithdrawl[msg.sender].amountBought == 0,
            "You have already participated in the purchase."
        );
        require(
            checkParticipationSignature(_signature, msg.sender, _allowance),
            "Invalid signature."
        );

        uint256 amountToBuy = (msg.value * 10 ** 18) / s_stall.tokenPriceInETH;

        if (amountToBuy > _allowance) revert Market__ExceedingTheAllowance();
        s_stall.totalTokensSold += amountToBuy;
        s_stall.totalETHRaised += msg.value;

        s_userToWithdrawl[msg.sender] = WithdrawalInfo({
            amountBought: amountToBuy,
            amountETHPaid: msg.value,
            isPortionWithdrawn: [false, false, false]
        });

        emit UserPurchase(msg.sender, amountToBuy);
    }

    /**
     * @notice Allows a user to withdraw unlocked stall tokens for specific vesting portions.
     * @param _portionIndexes An array of indices [0, 1, 2] representing the vesting portions to withdraw.
     */
    function userWithdrawStallTokens(
        uint256[] calldata _portionIndexes
    ) external nonReentrant {
        WithdrawalInfo storage withdrawlInfo = s_userToWithdrawl[msg.sender];
        require(
            withdrawlInfo.amountBought > 0,
            "Please participate in the purchase first."
        );
        require(
            block.timestamp > s_stall.vestingPortionsUnlockTime[0],
            "Tokens haven't yet been unlocked."
        );
        uint256 totalWithdrawAmount;

        for (uint256 i = 0; i < _portionIndexes.length; i++) {
            uint256 portionIndex = _portionIndexes[i];
            if (portionIndex >= 3)
                revert Market__PortionIndexIsOutOfUnlockRange();

            if (withdrawlInfo.isPortionWithdrawn[portionIndex])
                revert Market__TokensHaveBeenWithdrawn();

            if (
                block.timestamp <
                s_stall.vestingPortionsUnlockTime[portionIndex]
            ) revert Market__PortionHasNotBeenUnlocked();

            uint256 amount = (withdrawlInfo.amountBought *
                s_stall.vestingPercentPerPortion[portionIndex]) /
                s_stall.portionVestingPrecision;

            totalWithdrawAmount += amount;

            withdrawlInfo.isPortionWithdrawn[portionIndex] = true;
        }

        IERC20(s_stall.stallToken).safeTransfer(
            msg.sender,
            totalWithdrawAmount
        );

        emit UserWithdrawl(msg.sender, totalWithdrawAmount);
    }

    /**
     * @notice Allows the Stall Owner to withdraw the total ETH raised from the sale.
     * @dev Can only be called once by the Stall Owner after the sale has ended.
     */
    function stallerOwnerWithdrawYield()
        external
        onlyStallOwner
        onlyOnce(keccak256("stallerOwnerWithdrawYield"))
        nonReentrant
    {
        require(
            block.timestamp > s_stall.stallEnd,
            "The stall hasn't ended yet."
        );

        (bool success, ) = msg.sender.call{value: s_stall.totalETHRaised}("");

        if (!success) revert Market__StallOwnerFailsToWithdrawProfits();

        emit StallOwnerWithdrawProfits(msg.sender, s_stall.totalETHRaised);
    }

    /**
     * @notice Allows the Stall Owner to withdraw any unsold tokens after the sale ends.
     * @dev Can only be called once by the Stall Owner after the sale has ended.
     */
    function stallerOwnerWithdrawTheRemainingStallTokens()
        external
        onlyStallOwner
        onlyOnce(keccak256("stallerOwnerWithdrawTheRemainingStallTokens"))
    {
        require(
            block.timestamp > s_stall.stallEnd,
            "The stall hasn't ended yet."
        );

        uint256 remainAmount = s_stall.amountOfTokensToSell -
            s_stall.totalTokensSold;

        if (remainAmount > 0) {
            IERC20(s_stall.stallToken).safeTransfer(msg.sender, remainAmount);

            emit StallOwnerWithdrawRemainTokens(msg.sender, remainAmount);
        }
    }

    /* ------------------------------------------------------
                            Public
    ------------------------------------------------------ */
    /**
     * @notice Verifies the Admin's signature for stall registration.
     * @param signature The signature to verify.
     * @param user The address of the user attempting to register.
     * @return bool True if the signature is valid and matches the Admin address.
     */
    function checkRegistrationSignature(
        bytes memory signature,
        address user
    ) public view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(user, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return i_marketsCreater.owner() == messageHash.recover(signature);
    }

    /**
     * @notice Verifies the Admin's signature for purchase participation allowance.
     * @param signature The signature to verify.
     * @param user The address of the user.
     * @param amount The maximum purchase allowance amount (as signed by the Admin).
     * @return bool True if the signature is valid and matches the Admin address.
     */
    function checkParticipationSignature(
        bytes memory signature,
        address user,
        uint256 amount
    ) public view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(user, amount, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return i_marketsCreater.owner() == messageHash.recover(signature);
    }

    /* ------------------------------------------------------
                            Getter
    ------------------------------------------------------ */
    /**
     * @notice Returns the entire Stall configuration and status structure.
     * @return Stall The current state of the Stall.
     */
    function getStall() external view returns (Stall memory) {
        return s_stall;
    }

    /**
     * @notice Returns the address of the MarketsCreater contract.
     * @return address The MarketsCreater address.
     */
    function getMarketsCreaterAddr() external view returns (address) {
        return address(i_marketsCreater);
    }

    /**
     * @notice Returns the address of the LpTokenStakeV1 contract.
     * @return address The LpTokenStakeV1 address.
     */
    function getStakeAddr() external view returns (address) {
        return address(i_lpTokenStake);
    }
}
