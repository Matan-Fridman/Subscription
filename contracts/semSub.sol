// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Semaphore} from "./Semaphore.sol";
import {ISemaphoreVerifier} from "./ISemaphoreVerifier.sol";

struct ownedPackage {
    uint startTime;
    uint endTime;
    uint lastPaidMonth;
}

struct packageDetails {
    uint productId;
    uint packageGroupId;
    uint currentPackageIndex;
    mapping (string => uint) owners; // ens => packageId
    mapping (uint => ownedPackage) ownedPackages; // id => start time
    uint monthsToBePaid;
    uint lastPaidIndex;
}

interface IPalo {
    function transferToContract(address, uint256) external;
    function directTransfer(address, uint) external;
}

interface IproductsContract {
    function setupFee(uint)external view returns (uint);
    function monthly(uint)external view returns (uint);
    function duration(uint)external view returns (uint);
}

contract SempahoreSubscription is Semaphore {
    uint packageIdCounter = 0;
    mapping (uint256 => packageDetails) packages;
    address providerAddress;
    uint cancelNullifier;
    uint startNullifier;

    IPalo fundsContract;
    IproductsContract productsContract;

    constructor(ISemaphoreVerifier _verifier, IPalo _fundsContract, address _providerAddress, IproductsContract _productsContract)Semaphore(_verifier){
        fundsContract = _fundsContract;
        providerAddress =_providerAddress;
        productsContract = _productsContract;
    }

    function createSubscription(uint256 _commitment, uint256 packageId) public{
        uint setupFee = productsContract.setupFee(packageId);

        fundsContract.transferToContract(  // pay for first month in advance
            address(this),
            setupFee * 10 ** 18
        );
        _addMember(packageId, _commitment);
    }

    function startSubscription(SemaphoreProof calldata proof, uint256 packageId, string calldata ens)public{
        require(proof.scope == startNullifier, "nullifier not correct");
        validateProof(packageId, proof);
        uint indexOfPackage = packages[packageId].currentPackageIndex;
    
        packages[packageId].currentPackageIndex++;

        uint totalFee = productsContract.monthly(packageId) * productsContract.duration(packageId);
        uint durationInDays = productsContract.duration(packageId) * 31;

        fundsContract.transferToContract(msg.sender, totalFee);

        // set ens mapping to package index
        packages[packageId].owners[ens] = indexOfPackage;
        //set start time
        packages[packageId].ownedPackages[indexOfPackage].startTime = block.timestamp;
        //set end time
        uint durationInSeconds = durationInDays;
        packages[packageId].ownedPackages[indexOfPackage].endTime = block.timestamp + durationInSeconds;
    }

    function packageExists(uint packageId, string calldata ens) public view returns(bool){
        // if end time has passes
        uint indexOfPackage = packages[packageId].owners[ens];
        if(packages[packageId].ownedPackages[indexOfPackage].endTime < block.timestamp){
            return false;
        }
        return true;
    }

    function createProduct()public{
        _createGroup(packageIdCounter, address(this));
        // packages[packageIdCounter].packageGroupId = packageIdCounter;
        packages[packageIdCounter].currentPackageIndex = 0;
        packageIdCounter++;
    }

    function withdrawFunds() public {
        uint amount = getAvailableFunds();
        fundsContract.directTransfer(providerAddress, amount);
    }

    function getAvailableFunds() public returns(uint total){
        total = 0;
        for(uint i = 0; i <= packageIdCounter;i++){
            (uint totalAmount,uint lastPaidPerson) = getAvailableFundsForPackage(i);
            total += totalAmount;
            if(lastPaidPerson != 0){
                packages[i].lastPaidIndex = lastPaidPerson;
            }
        }
    }
    function viewAvailableFunds() public view returns(uint total){
        total = 0;
        for(uint i = 0; i <= packageIdCounter;i++){
            (uint totalAmount, uint lastPaidPerson) = getAvailableFundsForPackage(i);
            total += totalAmount;
        }
    }
    function getAvailableFundsForPackage(uint packageId)public view returns (uint total, uint lastPaidPerson){
        lastPaidPerson = packages[packageId].lastPaidIndex;   // last paid person - everyone before has been cleared
        uint packageAmount = packages[packageId].currentPackageIndex;
        uint monthlyFee = productsContract.monthly(packageId);
        uint monthsToPay = 0;

        for(uint i = lastPaidPerson; i < packageAmount;i++){
            uint startTime = packages[packageId].ownedPackages[i].startTime;
            uint endTime = packages[packageId].ownedPackages[i].endTime;
            bool expired = block.timestamp > packages[packageId].ownedPackages[i].endTime;
            bool canceled = secondsToMonths((endTime - startTime)) < 12;
            uint monthsAlreadyPaid = packages[packageId].ownedPackages[i].lastPaidMonth;
            // months passed since start minus months paid already
            uint monthsPassed = secondsToMonths((block.timestamp - startTime));
            // packages[packageId].ownedPackages[i].lastPaidMonth = monthsPassed;
            
            if(expired){
                if(canceled){
                    monthsToPay += secondsToMonths((endTime - startTime)) - monthsAlreadyPaid;
                    continue;
                }
                monthsToPay += 12 - monthsAlreadyPaid;
                lastPaidPerson = i;
            }
            else{
                monthsToPay += monthsPassed - monthsAlreadyPaid;
                lastPaidPerson = 0;
            }
        }
        total = monthsToPay * monthlyFee;
    }

    function cancelSubscription(SemaphoreProof calldata proof, uint packageId, string memory ens)public{
        require(proof.scope == cancelNullifier, "nullifier not correct");
        validateProof(packageId, proof);
        uint refundAmount = calculateRefund(packageId, ens);
        fundsContract.directTransfer(address(this), refundAmount);

        uint productId = packages[packageId].owners[ens];
        packages[packageId].ownedPackages[productId].endTime = block.timestamp;
    }

    function calculateRefund(uint packageId, string memory ens)public view returns(uint amount){
        uint productId = packages[packageId].owners[ens];
        uint startTime = packages[packageId].ownedPackages[productId].startTime;
        uint monthsOwed = 12 - monthsToSeconds(block.timestamp - startTime);
        uint monthly = productsContract.monthly(packageId);
        amount = monthly * monthsOwed;
    }

    function monthsToSeconds(uint256 months) public pure returns (uint256) {
        uint256 daysInMonth = 30; // Assuming 30 days in a month
        return months * daysInMonth * 84600;
    }
    function secondsToMonths(uint _seconds)public pure returns(uint){
        return _seconds / (30 * 84600);
    }
}