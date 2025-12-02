// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract Airdrop is EIP712 {
    using SafeERC20 for IERC20;

    error Airdrop__InvalidProof();
    error Airdrop__AlreadyClaimed();
    error Airdrop__InvalidSignature();

    address[] claimers;

    uint256 constant CLAIM_AMOUNT = 100 * 10 ** 18;

    bytes32 private immutable i_merkleRoot;
    IERC20 private immutable i_airdropToken;

    mapping(address claimer => bool claimed) private s_hasClaimed;

    bytes32 private constant MESSAGE_TYPEHASH =
        keccak256("AirdropClaim(address account, uint256 amount)");

    struct AirdropClaim {
        address account;
        uint256 amount;
    }

    event Claim(address indexed account, uint256 amount);

    constructor(
        bytes32 merkleRoot,
        IERC20 airdropToken
    ) EIP712("Airdrop", "1") {
        i_merkleRoot = merkleRoot;
        i_airdropToken = airdropToken;
    }

    function claim(
        address account,
        bytes32[] calldata merkleProof,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (s_hasClaimed[account]) revert Airdrop__AlreadyClaimed();

        // 替他人代领需要验证签名
        if (msg.sender != account) {
            if (
                !_isValidSignature(
                    account,
                    getMessageHash(account, CLAIM_AMOUNT),
                    v,
                    r,
                    s
                )
            ) revert Airdrop__InvalidSignature();
        }

        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(account, CLAIM_AMOUNT)))
        );

        if (!MerkleProof.verify(merkleProof, i_merkleRoot, leaf))
            revert Airdrop__InvalidProof();

        s_hasClaimed[account] = true;

        emit Claim(account, CLAIM_AMOUNT);

        i_airdropToken.safeTransfer(account, CLAIM_AMOUNT);
    }

    function getMessageHash(
        address account,
        uint256 amount
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MESSAGE_TYPEHASH,
                        AirdropClaim({account: account, amount: amount})
                    )
                )
            );
    }

    function _isValidSignature(
        address account,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        (address actualSigner, , ) = ECDSA.tryRecover(digest, v, r, s);
        return actualSigner == account;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return i_merkleRoot;
    }

    function getAirdropToken() external view returns (IERC20) {
        return i_airdropToken;
    }
}
