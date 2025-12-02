// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Airdrop} from "../../src/Airdrop.sol";
import {Minecraft} from "../../src/MinecraftCoin.sol";
import {DeployAirdrop} from "../../script/airdrop/DeployAirdrop.s.sol";
import {ZkSyncChainChecker} from "lib/foundry-devops/src/ZkSyncChainChecker.sol";

contract AirdropTest is ZkSyncChainChecker, Test {
    Airdrop public airdrop;
    Minecraft public token;

    bytes32 public ROOT =
        0x8c6b4837e779336b41dfe83f664b2abcfa20bd688e5b297c8510fb8cf2d0c3d5;

    uint256 public AMOUNT_TO_CLAIM = 100 * 10 ** 18;
    uint256 public AIRDROP_BAL = 400 * 10 ** 18;

    bytes32 proofOne =
        0x91ca955de9f6cc63db9e7369302acfbbd2c9c7ca7c6d3cc8cf9c9acaead52c6c;
    bytes32 proofTwo =
        0x118bf10c3828a1483f8716aea0b41cc5806780b3078c2baf804844325423a6dc;

    bytes32[] public PROOF = [proofOne, proofTwo];

    address user;

    uint256 userPrivateKey;

    address gasPayer;

    function setUp() public {
        if (isZkSyncChain()) {
            token = new Minecraft();
            airdrop = new Airdrop(ROOT, token);

            token.mint(token.owner(), AIRDROP_BAL);
            token.transfer(address(airdrop), AIRDROP_BAL);
        } else {
            DeployAirdrop deployer = new DeployAirdrop();
            (airdrop, token) = deployer.deployAirdrop();
        }

        (user, userPrivateKey) = makeAddrAndKey("user");
        gasPayer = makeAddr("gasPayer");
    }

    function signMessage(
        uint256 privateKey,
        address account
    ) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashedMessage = airdrop.getMessageHash(
            account,
            AMOUNT_TO_CLAIM
        );
        (v, r, s) = vm.sign(privateKey, hashedMessage);
    }

    function testUserOrGasPayerCanClaimSuccessful() public {
        vm.startPrank(user);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(userPrivateKey, user);
        vm.stopPrank();
        vm.prank(gasPayer);
        airdrop.claim(user, PROOF, v, r, s);
        assertEq(token.balanceOf(user), AMOUNT_TO_CLAIM);
        assertEq(token.balanceOf(address(airdrop)), 300 * 10 ** 18);
    }

    function testUserCannotClaimItRepeatedly() public {
        vm.startPrank(user);
        airdrop.claim(user, PROOF, 0, bytes32(0), bytes32(0));
        vm.expectRevert(Airdrop.Airdrop__AlreadyClaimed.selector);
        airdrop.claim(user, PROOF, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }
}
