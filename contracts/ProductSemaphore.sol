// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Semaphore} from "./Semaphore.sol";
import {ISemaphoreVerifier} from "./ISemaphoreVerifier.sol";


contract ProductsSemaphore is Semaphore {
    // if someone gets ur commitment, they wont be able to redeem unless they know the product, given the productid hash is the scope
    uint scope = 12055883547725688507598382652213303367251128561332258200425165377290225199166;

    /// @dev Initializes the Semaphore verifier used to verify the user's ZK proofs.
    /// @param _verifier: Semaphore verifier addresse.
    constructor(ISemaphoreVerifier _verifier) Semaphore(_verifier) {
        _createGroup(1, address(this));
    }

    function deposit(uint amount, uint256 commitment)public payable{
        require(amount == 1 || amount == 10 || amount == 100, "Amount is nt valid");
        require(amount <= msg.value - 1);
        this.addMember(amount, commitment);
    }

    function withdraw(SemaphoreProof calldata proof, uint groupId) public {
        require(scope == proof.scope, "scope not correct");
        if (groups[groupId].nullifiers[proof.nullifier]) {
            revert Semaphore__YouAreUsingTheSameNullifierTwice();
        }

        // The function will revert if the proof is not verified successfully.
        if (!verifyProof(groupId, proof)) {
            revert Semaphore__InvalidProof();
        }

        groups[groupId].nullifiers[proof.nullifier] = true;

        payable(msg.sender).transfer(groupId);
    }

    function balance()public view returns (uint){
        return address(this).balance;
    }

    // user finishes stripe payment, cloud calls this func and returns commitment. user gets callback to app with commitment, which calls redeemProduct
    function buyProduct(uint groupId, uint256 commitment) public {
        this.addMember(groupId, commitment);
    }

    function redeemProduct(SemaphoreProof calldata proof, uint groupId) public {
        require(scope == proof.scope, "scope not correct");
        if (groups[groupId].nullifiers[proof.nullifier]) {
            revert Semaphore__YouAreUsingTheSameNullifierTwice();
        }

        // The function will revert if the proof is not verified successfully.
        if (!verifyProof(groupId, proof)) {
            revert Semaphore__InvalidProof();
        }

        groups[groupId].nullifiers[proof.nullifier] = true;

        payable(msg.sender).transfer(groupId);
    }
    
}
