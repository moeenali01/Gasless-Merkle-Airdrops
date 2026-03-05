// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { EyesToken } from "../src/EyesToken.sol";
import { MerkleAirdrop } from "../src/Merkle_Airdrop.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployMerkleAirdrop
 * @author Moin Shahid
 * @notice Deployment script that deploys the EYES token and MerkleAirdrop contract,
 *         then funds the airdrop contract with the full token supply.
 */
contract DeployMerkleAirdrop is Script {
    /// @notice Total supply of EYES tokens: 100 million with 18 decimals.
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;

    /**
     * @notice Deploys both contracts and transfers the airdrop allocation.
     * @param merkleRoot The Merkle root for the airdrop eligibility tree.
     * @return token The deployed EyesToken contract.
     * @return airdrop The deployed MerkleAirdrop contract.
     */
    function deploy(bytes32 merkleRoot) public returns (EyesToken token, MerkleAirdrop airdrop) {
        vm.startBroadcast();

        // Deploy the EYES token — entire supply minted to deployer
        token = new EyesToken(INITIAL_SUPPLY);
        console.log("EyesToken deployed at:", address(token));

        // Deploy the MerkleAirdrop contract
        airdrop = new MerkleAirdrop(merkleRoot, IERC20(address(token)));
        console.log("MerkleAirdrop deployed at:", address(airdrop));

        // Transfer the full supply to the airdrop contract
        token.transfer(address(airdrop), INITIAL_SUPPLY);
        console.log("Transferred %s tokens to airdrop contract", INITIAL_SUPPLY);

        vm.stopBroadcast();
    }

    function run() external returns (EyesToken, MerkleAirdrop) {
        // Default merkle root — replace with actual root before mainnet deployment
        bytes32 merkleRoot = vm.envOr("MERKLE_ROOT", bytes32(0));
        require(merkleRoot != bytes32(0), "Set MERKLE_ROOT env variable");
        return deploy(merkleRoot);
    }
}
