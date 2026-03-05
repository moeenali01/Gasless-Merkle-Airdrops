// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerkleAirdrop} from "../src/Merkle_Airdrop.sol";
import {EyesToken} from "../src/EyesToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MerkleAirdropTest is Test {
    MerkleAirdrop public airdrop;
    EyesToken public token;

    // Test accounts
    address public deployer;
    uint256 public claimantPrivateKey;
    address public claimant;
    address public relayer;

    // Airdrop parameters
    uint256 public constant CLAIM_AMOUNT = 25 ether;
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    // Merkle tree values (for a tree with a single leaf: claimant + CLAIM_AMOUNT)
    bytes32 public merkleRoot;
    bytes32[] public proof;

    function setUp() public {
        deployer = makeAddr("deployer");
        claimantPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        claimant = vm.addr(claimantPrivateKey);
        relayer = makeAddr("relayer");

        // Build a simple Merkle tree with 4 leaves
        // Leaf 0: claimant, CLAIM_AMOUNT
        // Leaf 1: user1, CLAIM_AMOUNT
        // Leaf 2: user2, CLAIM_AMOUNT
        // Leaf 3: user3, CLAIM_AMOUNT
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        bytes32 leaf0 = keccak256(bytes.concat(keccak256(abi.encode(claimant, CLAIM_AMOUNT))));
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(user1, CLAIM_AMOUNT))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(user2, CLAIM_AMOUNT))));
        bytes32 leaf3 = keccak256(bytes.concat(keccak256(abi.encode(user3, CLAIM_AMOUNT))));

        // Build tree: hash pairs sorted to match OpenZeppelin's MerkleProof.verify
        bytes32 hash01 = _hashPair(leaf0, leaf1);
        bytes32 hash23 = _hashPair(leaf2, leaf3);
        merkleRoot = _hashPair(hash01, hash23);

        // Proof for leaf0: [leaf1, hash23]
        proof.push(leaf1);
        proof.push(hash23);

        // Deploy contracts
        vm.startPrank(deployer);
        token = new EyesToken(INITIAL_SUPPLY);
        airdrop = new MerkleAirdrop(merkleRoot, IERC20(address(token)));
        token.transfer(address(airdrop), INITIAL_SUPPLY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_sets_merkle_root() public view {
        assertEq(airdrop.getMerkleRoot(), merkleRoot);
    }

    function test_constructor_sets_airdrop_token() public view {
        assertEq(address(airdrop.getAirdropToken()), address(token));
    }

    function test_airdrop_contract_has_tokens() public view {
        assertEq(token.balanceOf(address(airdrop)), INITIAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claim_succeeds_with_valid_proof_and_signature() public {
        uint256 balanceBefore = token.balanceOf(claimant);

        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);

        assertEq(token.balanceOf(claimant), balanceBefore + CLAIM_AMOUNT);
    }

    function test_claim_emits_claimed_event() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit MerkleAirdrop.Claimed(claimant, CLAIM_AMOUNT);

        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);
    }

    function test_claim_marks_account_as_claimed() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        assertFalse(airdrop.hasClaimed(claimant));

        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);

        assertTrue(airdrop.hasClaimed(claimant));
    }

    function test_claim_can_be_called_by_relayer() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        // Relayer submits on behalf of claimant
        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);

        assertEq(token.balanceOf(claimant), CLAIM_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claim_reverts_on_double_claim() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);

        vm.expectRevert(MerkleAirdrop.MerkleAirdrop__AlreadyClaimed.selector);
        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);
    }

    function test_claim_reverts_with_invalid_signature() public {
        // Sign with a different private key
        uint256 wrongKey = 0xdead;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(wrongKey, claimant, CLAIM_AMOUNT);

        vm.expectRevert(MerkleAirdrop.MerkleAirdrop__InvalidSignature.selector);
        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, proof, v, r, s);
    }

    function test_claim_reverts_with_wrong_amount() public {
        uint256 wrongAmount = 50 ether;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, wrongAmount);

        vm.expectRevert(MerkleAirdrop.MerkleAirdrop__InvalidProof.selector);
        vm.prank(relayer);
        airdrop.claim(claimant, wrongAmount, proof, v, r, s);
    }

    function test_claim_reverts_with_invalid_proof() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xbad));

        vm.expectRevert(MerkleAirdrop.MerkleAirdrop__InvalidProof.selector);
        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, badProof, v, r, s);
    }

    function test_claim_reverts_with_empty_proof() public {
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(claimantPrivateKey, claimant, CLAIM_AMOUNT);

        bytes32[] memory emptyProof = new bytes32[](0);

        vm.expectRevert(MerkleAirdrop.MerkleAirdrop__InvalidProof.selector);
        vm.prank(relayer);
        airdrop.claim(claimant, CLAIM_AMOUNT, emptyProof, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                          MESSAGE HASH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getMessageHash_returns_consistent_hash() public view {
        bytes32 hash1 = airdrop.getMessageHash(claimant, CLAIM_AMOUNT);
        bytes32 hash2 = airdrop.getMessageHash(claimant, CLAIM_AMOUNT);
        assertEq(hash1, hash2);
    }

    function test_getMessageHash_differs_for_different_accounts() public view {
        bytes32 hash1 = airdrop.getMessageHash(claimant, CLAIM_AMOUNT);
        bytes32 hash2 = airdrop.getMessageHash(relayer, CLAIM_AMOUNT);
        assertNotEq(hash1, hash2);
    }

    function test_getMessageHash_differs_for_different_amounts() public view {
        bytes32 hash1 = airdrop.getMessageHash(claimant, CLAIM_AMOUNT);
        bytes32 hash2 = airdrop.getMessageHash(claimant, CLAIM_AMOUNT + 1);
        assertNotEq(hash1, hash2);
    }

    /*//////////////////////////////////////////////////////////////
                          EYES TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_eyes_token_name() public view {
        assertEq(token.name(), "EYES");
    }

    function test_eyes_token_symbol() public view {
        assertEq(token.symbol(), "EYES");
    }

    function test_eyes_token_initial_supply() public view {
        // Deployer transferred all to airdrop, so deployer balance is 0
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Signs an AirdropClaim message using EIP-712.
    function _signClaim(uint256 privateKey, address account, uint256 amount)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 digest = airdrop.getMessageHash(account, amount);
        (v, r, s) = vm.sign(privateKey, digest);
    }

    /// @dev Hashes a pair of bytes32 values in sorted order (matching OpenZeppelin MerkleProof).
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
