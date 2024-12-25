// SPDX-License-Identifier:MIT
pragma solidity 0.8.26;

import {Semaphore} from "./Semaphore.sol";
import {ISemaphoreVerifier} from "./ISemaphoreVerifier.sol";
import {SemaphoreGroups} from "./SemaphoreGroups.sol";
import {MIN_DEPTH, MAX_DEPTH} from "./Constants.sol";

struct Box {
    uint boxFund;
    address owner;
}

contract SemaphorePayboxTC is Semaphore {
    uint scope = 12055883547725688507598382652213303367251128561332258200425165377290225199166;
    uint currentGroupId = 101;
    mapping (uint => Box) boxes;
    /// @dev Initializes the Semaphore verifier used to verify the user's ZK proofs.
    /// @param _verifier: Semaphore verifier addresse.
    constructor(ISemaphoreVerifier _verifier) Semaphore(_verifier) {
        for(uint i=1;i<=100;i++){
            _createGroup(i, address(this));
        }
    }
    function getOwner(uint groupId)public view returns(address){
        return boxes[groupId].owner;
    }
    function getBalance(uint groupId)public view returns(uint){
        return boxes[groupId].boxFund;
    }
    function createBox() public {
        boxes[currentGroupId].owner = msg.sender;
        currentGroupId++;
    }

    function deposit(uint amount, uint256 commitment)public payable{
        require(1 <= amount && amount <= 100, "Amount is not valid");
        require(amount <= msg.value - 1);
        this.addMember(amount, commitment);
    }

    function addAmountToBox(SemaphoreProof calldata proof, uint groupId, uint boxId)public {
        require(scope == proof.scope, "scope not correct");
        if (groups[groupId].nullifiers[proof.nullifier]) {
            revert Semaphore__YouAreUsingTheSameNullifierTwice();
        }

        // The function will revert if the proof is not verified successfully.
        if (!verifyProof(groupId, proof)) {
            revert Semaphore__InvalidProof();
        }

        groups[groupId].nullifiers[proof.nullifier] = true;
        boxes[boxId].boxFund += groupId;
    }
    function withdraw(uint boxId, uint amountToWithdraw)public{
        require(boxes[boxId].owner == msg.sender, "ur not the owner of the box");
        uint amount;
        if(amountToWithdraw > boxes[boxId].boxFund){    // if amount req is bigger than fund give everything in box
            payable(msg.sender).transfer(boxes[boxId].boxFund);
            boxes[boxId].boxFund = 0;
        }
        else{   // if amount is smaller than fund give amount
            payable(msg.sender).transfer(amount);
            boxes[boxId].boxFund -= amount;
        }
    }

    function balance()public view returns (uint){
        return address(this).balance;
    }

}
