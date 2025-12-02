// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Airdrop, IERC20} from "../../src/Airdrop.sol";
import {Minecraft} from "../../src/MinecraftCoin.sol";

contract DeployAirdrop is Script {
    bytes32 private s_merkleRoot =
        0x8c6b4837e779336b41dfe83f664b2abcfa20bd688e5b297c8510fb8cf2d0c3d5;

    uint256 TOTAL_AMOUNT = 400 * 10 ** 18;

    function run() external returns (Airdrop, Minecraft) {
        return deployAirdrop();
    }

    function deployAirdrop() public returns (Airdrop, Minecraft) {
        vm.startBroadcast();
        Minecraft token = new Minecraft();

        Airdrop airdrop = new Airdrop(s_merkleRoot, token);

        token.mint(token.owner(), TOTAL_AMOUNT);

        token.transfer(address(airdrop), TOTAL_AMOUNT);
        vm.stopBroadcast();
        return (airdrop, token);
    }
}
