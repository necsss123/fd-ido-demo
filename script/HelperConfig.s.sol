// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LpToken} from "../test/mocks/LpToken.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    address public constant FOUNDRY_DEFAULT_SENDER =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        LpToken eth_minecraft_lp;
        LpToken sol_minecraft_lp;
        address defaultAccount;
        uint256 deployerKey;
    }

    // uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    NetworkConfig public localNetworkConfig;

    function getConfig(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == ANVIL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (address(localNetworkConfig.eth_minecraft_lp) != address(0)) {
            return localNetworkConfig;
        }
        vm.startBroadcast(DEFAULT_ANVIL_KEY);
        LpToken eth_lp = new LpToken();
        LpToken sol_lp = new LpToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            eth_minecraft_lp: eth_lp,
            sol_minecraft_lp: sol_lp,
            defaultAccount: FOUNDRY_DEFAULT_SENDER,
            deployerKey: DEFAULT_ANVIL_KEY
        });
        return localNetworkConfig;
    }
}
