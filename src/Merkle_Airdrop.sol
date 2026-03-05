// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MerkleAirdrop
 * @author Moin Shahid
 * @notice A gas-efficient airdrop contract that distributes ERC20 tokens using Merkle proofs and EIP-712 signatures.
 * @dev Eligible recipients are encoded into a Merkle tree off-chain. To claim, a user must provide:
 *      1. A valid Merkle proof proving their (account, amount) leaf exists in the tree.
 *      2. An EIP-712 typed signature from the claiming account, allowing a third party (e.g. a relayer)
 *         to submit the transaction on behalf of the claimant (gas sponsorship).
 *      Tokens are transferred via SafeERC20 to prevent silent failures on non-standard tokens.
 */
contract MerkleAirdrop is EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the supplied Merkle proof does not verify against the stored root.
    error MerkleAirdrop__InvalidProof();

    /// @notice Thrown when the account has already claimed its airdrop allocation.
    error MerkleAirdrop__AlreadyClaimed();

    /// @notice Thrown when the EIP-712 signature does not match the claiming account.
    error MerkleAirdrop__InvalidSignature();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC20 token being distributed in this airdrop.
    IERC20 private immutable i_airdropToken;

    /// @notice The root of the Merkle tree containing all eligible (account, amount) pairs.
    bytes32 private immutable i_merkleRoot;

    /// @notice Tracks whether an address has already claimed its allocation.
    mapping(address => bool) private s_hasClaimed;

    /// @dev EIP-712 typehash for the AirdropClaim struct: keccak256("AirdropClaim(address account,uint256 amount)").
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("AirdropClaim(address account,uint256 amount)");

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Represents a claim request that must be signed by the claimant via EIP-712.
    /// @param account The address eligible to receive tokens.
    /// @param amount The number of tokens (in wei) the account is entitled to.
    struct AirdropClaim {
        address account;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an account successfully claims its airdrop tokens.
    /// @param account The address that received the tokens.
    /// @param amount The number of tokens transferred.
    event Claimed(address account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the airdrop contract with a Merkle root and the token to distribute.
     * @param merkleRoot The root hash of the Merkle tree encoding all eligible claims.
     * @param airdropToken The ERC20 token contract that will be airdropped.
     * @dev The EIP-712 domain is set to name="Merkle Airdrop", version="1.0.0".
     */
    constructor(bytes32 merkleRoot, IERC20 airdropToken) EIP712("Merkle Airdrop", "1.0.0") {
        i_merkleRoot = merkleRoot;
        i_airdropToken = airdropToken;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims airdrop tokens on behalf of `account` using a Merkle proof and an EIP-712 signature.
     * @dev The signature allows a third-party relayer to submit the claim transaction, paying gas on behalf
     *      of the claimant. The function enforces a checks-effects-interactions pattern:
     *      1. Check: revert if already claimed, verify signature, verify Merkle proof.
     *      2. Effect: mark the account as claimed.
     *      3. Interaction: transfer tokens via SafeERC20.
     * @param account The address claiming the airdrop (must match the signer of the EIP-712 message).
     * @param amount The amount of tokens to claim (must match the Merkle leaf).
     * @param merkleProof An array of sibling hashes forming the path from the leaf to the Merkle root.
     * @param v The recovery byte of the ECDSA signature.
     * @param r The first 32 bytes of the ECDSA signature.
     * @param s The second 32 bytes of the ECDSA signature.
     */
    function claim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        // Check: revert if the account has already claimed
        if (s_hasClaimed[account]) {
            revert MerkleAirdrop__AlreadyClaimed();
        }

        // Check: verify the EIP-712 signature belongs to the claiming account
        if (!_isValidSignature(account, getMessageHash(account, amount), v, r, s)) {
            revert MerkleAirdrop__InvalidSignature();
        }

        // Check: verify the Merkle proof
        // The leaf is double-hashed to prevent second preimage attacks
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
        if (!MerkleProof.verify(merkleProof, i_merkleRoot, leaf)) {
            revert MerkleAirdrop__InvalidProof();
        }

        // Effect: mark as claimed before transferring (reentrancy protection)
        s_hasClaimed[account] = true;
        emit Claimed(account, amount);

        // Interaction: transfer airdrop tokens to the claimant
        i_airdropToken.safeTransfer(account, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Computes the EIP-712 typed data hash for a given claim, used for signature verification.
     * @param account The address of the claimant.
     * @param amount The token amount being claimed.
     * @return The fully encoded EIP-712 hash ready to be signed or verified.
     */
    function getMessageHash(address account, uint256 amount) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(MESSAGE_TYPEHASH, AirdropClaim({ account: account, amount: amount })))
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the Merkle root used to verify airdrop eligibility.
    function getMerkleRoot() external view returns (bytes32) {
        return i_merkleRoot;
    }

    /// @notice Returns the ERC20 token being distributed.
    function getAirdropToken() external view returns (IERC20) {
        return i_airdropToken;
    }

    /// @notice Returns whether the given account has already claimed its airdrop.
    /// @param account The address to check.
    function hasClaimed(address account) external view returns (bool) {
        return s_hasClaimed[account];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that the recovered signer matches the expected account.
     * @dev Uses ECDSA.tryRecover to safely recover the signer without reverting on invalid signatures.
     * @param signer The expected signer (the airdrop claimant).
     * @param digest The EIP-712 hash that was signed.
     * @param _v Recovery byte of the signature.
     * @param _r First 32 bytes of the signature.
     * @param _s Second 32 bytes of the signature.
     * @return True if the recovered address matches `signer`, false otherwise.
     */
    function _isValidSignature(
        address signer,
        bytes32 digest,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        internal
        pure
        returns (bool)
    {
        (address actualSigner,,) = ECDSA.tryRecover(digest, _v, _r, _s);
        return (actualSigner == signer);
    }
}
