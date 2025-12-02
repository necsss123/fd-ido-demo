// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import "../../src/MinecraftCoin.sol";

contract MinecraftTest is Test {
    Minecraft projectToken;

    function setUp() external {
        projectToken = new Minecraft();
    }

    function testInitialIsSuccess() public {
        projectToken.mint(address(this), 1000 * 1e18);

        assertEq(projectToken.owner(), address(this));
        assertEq(projectToken.totalSupply(), 1000 * 1e18);
    }
}
