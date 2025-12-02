// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Market} from "./Market.sol";

contract MarketsCreater is Ownable {
    address private immutable i_stake;

    address[] private markets;

    mapping(address => bool) private isMarketExist;

    event MarketCreate(address indexed market);

    constructor(address _stake) Ownable(msg.sender) {
        i_stake = _stake;
    }

    function createMarket() external onlyOwner {
        Market market = new Market(i_stake);
        isMarketExist[address(market)] = true;
        markets.push(address(market));

        emit MarketCreate(address(market));
    }

    function getStakeAddr() external view returns (address) {
        return i_stake;
    }

    function getMarketsFromIndex(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory) {
        require(end > start, "Invalid Input.");

        address[] memory marketsSlice = new address[](end - start);

        uint256 index = 0;
        for (uint256 i = start; i < end; i++) {
            marketsSlice[index] = markets[i];
            index++;
        }

        return marketsSlice;
    }

    function getMarketsNum() external view returns (uint256) {
        return markets.length;
    }

    function queryMarketIsExist(address _market) external view returns (bool) {
        return isMarketExist[_market];
    }
}
