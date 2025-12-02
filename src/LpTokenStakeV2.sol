// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

contract LpTokenStakeV2 is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient
{
    /* Functions */
    function initialize() public reinitializer(2) {
        __Ownable_init(msg.sender);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
