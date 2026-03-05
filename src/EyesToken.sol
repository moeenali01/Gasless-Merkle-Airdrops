// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EyesToken (EYES)
 * @author Moin Shahid
 * @notice An ERC20 token distributed via a Merkle-proof-based airdrop.
 * @dev The deployer receives the initial supply and is expected to transfer
 *      the airdrop allocation to the MerkleAirdrop contract.
 */
contract EyesToken is ERC20, Ownable {
    /**
     * @notice Deploys the EYES token and mints the initial supply to the deployer.
     * @param initialSupply The total number of tokens (in wei) to mint at deployment.
     */
    constructor(uint256 initialSupply) ERC20("EYES", "EYES") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }
}
