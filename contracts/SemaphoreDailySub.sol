// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Semaphore} from "./Semaphore.sol";
import {ISemaphoreVerifier} from "./ISemaphoreVerifier.sol";

struct ownedPackage {
    uint startTime;
    uint endTime;
    uint lastPaidMonth;
}

interface IPalo {
    function directTransfer(address, uint256) external;
    function directTransferFromContract(address, uint) external;
    function transferFromUser(address, address, uint)external;
}

interface IproductsContract {
    function getSetupFee(uint)external view returns (uint);
    function getMonthly(uint)external view returns (uint);
    function getDuration(uint)external view returns (uint);
    function createProduct(uint, uint, uint, uint)external;
}

contract SempahoreSubscription is Semaphore {
    uint productCounter = 1;
    mapping (uint256 => uint256) startingDates; //prodId => starting moment _ 10002 => timestamp
    mapping (uint256 => uint256) lastPaidDate; //prodId => last paid day _ 10002 => 243
    mapping (uint256 => uint256) lastFullyPaidDays; //prodId => last paid day _ 10002 => 243
    mapping (string => uint256) owners; // ens => productId. this way we can extract the days passed since subscription
    mapping (uint256 => uint) canceledSubscriptionAmounts;  // amount of subs canceled per full prod id;
    mapping (uint256 => bool) productIdExists;
    uint cancelNullifier = 691557786976560214689293887019892989638751705460776445044671668036948253559;
    uint startNullifier = 12055883547725688507598382652213303367251128561332258200425165377290225199166;
    address providerAddress;

    IPalo fundsContract;
    IproductsContract productsContract;

    constructor(ISemaphoreVerifier _verifier, IPalo _fundsContract, address _providerAddress, IproductsContract _productsContract)Semaphore(_verifier){
        fundsContract = _fundsContract;
        providerAddress =_providerAddress;
        productsContract = _productsContract;
    }
    // takes in just the groupId of the product so 10002
    function createSubscription(uint256 _commitment, uint256 productId, address userWallet) public returns (uint){
        require(productIdExists[productId], "product doesnt exist");
        uint setupFee = productsContract.getSetupFee(productId);
        uint monthlyFee = productsContract.getMonthly(productId);

        uint fullProductId;
        if(getGroupAdmin(productId*100000+1) == address(0x0)){    // if prod id doesnt have a first day group yet
            startingDates[productId] = block.timestamp;
            fullProductId = productId * 100000 + 1;
            _createGroup(fullProductId, providerAddress);
        }
        else{   // if product already exists, so this is not the first subscriber
            uint productFirstDay = startingDates[productId];
            uint daysPassed = getRoundedNum((block.timestamp - productFirstDay), 86400);    // days passed since product's day 1
            fullProductId = productId * 100000 + daysPassed;
        }
        fundsContract.transferFromUser(  // pay for first month in advance
            userWallet,
            address(this),
            monthlyFee * 12 + setupFee
        );
        _addMember(fullProductId, _commitment);
        return fullProductId;
    }
// 0xdA36b4dA80a282dfD73E3E452817eDd72022c955,0x633e25e394AbE7c00C82045311cC5Eef4bC1f2fA,0x9A0d73b6D2D54fdC66AdD5b73495DB059Ce24C5c, 0x692e320a1C2826e7d980943E87C167805b6ab8C4
    function startSubscription(SemaphoreProof calldata proof, uint256 productId, string calldata ens)public{
        require(proof.scope == startNullifier, "nullifier not correct");
        require(productIdExists[productId], "product doesnt exist");

        uint productFirstDay = startingDates[productId];
        uint daysPassed = getRoundedNum((block.timestamp - productFirstDay), 86400);    // days passed since product's day 1
        require(daysPassed <= 1, "too late man");
        uint fullProductId = productId * 100000 + daysPassed; // go from 10002 to 1000200000 and add current day
        
        validateProof(fullProductId, proof);

        // set ens mapping to package index
        owners[ens] = fullProductId;
    }

    function packageExists(uint productId, string calldata ens) public view returns(bool){
        uint fullProductId = owners[ens];
        if(fullProductId == 0 ){
            return false;
        }
        uint dayOfStart = fullProductId - productId * 100000; // from 1000200345 to 345
        uint daysPassedSinceStart = getRoundedNum((block.timestamp - startingDates[productId]), 84600); // were on day 850 compared to start dates
        bool expired = daysPassedSinceStart - dayOfStart > 365; // were on 850 we started on 345, 850 - 345 is more than a 365

        if(expired){
            return false;
        }
        return true;
    }

    function productExists(uint prodId) public view returns(bool){
        return productIdExists[prodId];
    }

    function createProduct()public returns(uint){
        uint productId = 10000 + productCounter;    // 10003 prodId
        productIdExists[productId] = true;
        productsContract.createProduct(3, 50, 12, productId);
        productCounter++;
        return productId;
    }

    function withdrawFunds() public {
        uint totalAmount = 0;
        for(uint product = 10001; productIdExists[product]; product++){
            totalAmount += getAvailableFundsForPackage(product);
        }
        fundsContract.directTransferFromContract(providerAddress, totalAmount);
    }

    function viewAvailableFunds() public view returns(uint totalAmount){
        totalAmount = 0;
        for(uint product = 10001; productIdExists[product]; product++){
            totalAmount += calculateAvailableFunds(product);
        }
    }

    function getAvailableFundsForPackage(uint productId)public returns (uint){
        uint daysPassedSinceStart = getRoundedNum((block.timestamp - startingDates[productId]), 84600); // were on day 850 compared to start dates
        uint fullProductId = productId * 100000 + 1; //full prod id for first day
        uint months = 0;
        uint day = 1 + lastFullyPaidDays[productId];
        uint currentMonth = getRoundedNum((daysPassedSinceStart - day), 30);
        if(currentMonth > 12){
            currentMonth = 12;
        }
        // i.e while 1000200035 - 1000300000 = 35 is smaller than today keep checking,
        // if the groupId is after today we dont need to check
        for(uint DAY = day; DAY < daysPassedSinceStart; DAY ++){
            if(getMerkleTreeSize(fullProductId) == 0){
                fullProductId ++;
                continue;
            }
            uint amountOfMonthsPaidLastTime = getRoundedNum(lastPaidDate[productId] - DAY, 30);
            if(amountOfMonthsPaidLastTime > 12){ // CHECK ROUNDING
                amountOfMonthsPaidLastTime = 12;
            }
            months += 
            (getMerkleTreeSize(fullProductId) - canceledSubscriptionAmounts[fullProductId])
            *
            (currentMonth - amountOfMonthsPaidLastTime);
            fullProductId ++;
            if(currentMonth >= 12 ){
                lastFullyPaidDays[productId] = DAY;
            }
            if(getRoundedNum((daysPassedSinceStart - DAY), 30) < 12){ // CHECK ROUNDING
                currentMonth = getRoundedNum((daysPassedSinceStart - DAY), 30);
            }
        }
        lastPaidDate[productId] = daysPassedSinceStart;
        return (months * productsContract.getMonthly(productId));
    }
    function calculateAvailableFunds(uint productId)public view returns (uint){
        uint daysPassedSinceStart = getRoundedNum((block.timestamp - startingDates[productId]), 84600); // were on day 850 compared to start dates
        uint fullProductId = productId * 100000 + 1; //full prod id for first day
        uint months = 0;
        uint day = lastFullyPaidDays[productId];
        uint currentMonth = getRoundedNum((daysPassedSinceStart - day), 30);
        if(currentMonth > 12){
            currentMonth = 12;
        }
        // i.e while 1000200035 - 1000300000 = 35 is smaller than today keep checking,
        // if the groupId is after today we dont need to check
        for(uint DAY = day; DAY < daysPassedSinceStart; DAY ++){
            if(getMerkleTreeSize(fullProductId) == 0){
                fullProductId ++;
                continue;
            }
            uint amountOfMonthsPaidLastTime = getRoundedNum(lastPaidDate[productId] - DAY, 30);
            if(amountOfMonthsPaidLastTime > 12){ // CHECK ROUNDING
                amountOfMonthsPaidLastTime = 12;
            }
            months += 
            (getMerkleTreeSize(fullProductId) - canceledSubscriptionAmounts[fullProductId])
            *
            (currentMonth - amountOfMonthsPaidLastTime);
            fullProductId ++;
            if(getRoundedNum((daysPassedSinceStart - DAY), 30) < 12){ // CHECK ROUNDING
                currentMonth = getRoundedNum((daysPassedSinceStart - DAY), 30);
            }
        }
        return (months * productsContract.getMonthly(productId));
    }

    function cancelSubscription(SemaphoreProof calldata proof, uint productId, string memory ens)public{
        require(proof.scope == cancelNullifier, "nullifier not correct");
        validateProof(productId, proof);
        uint refundAmount = calculateRefund(productId, ens);
        fundsContract.directTransferFromContract(msg.sender, refundAmount);

        uint fullProductId = owners[ens];
        canceledSubscriptionAmounts[fullProductId] ++;
        owners[ens] = 0;
    }

    function calculateRefund(uint productId, string memory ens)public view returns(uint amount){
        uint fullProductId = owners[ens];
        uint daysPassed = fullProductId - productId * 100000; // 1000200034 - 1000200000 = 34 days have passed
        uint monthsOwed = 12 - getRoundedNum(daysPassed, 30);
        uint monthly = productsContract.getMonthly(productId);
        amount = monthly * monthsOwed;
    }

    function getRoundedNum(uint num1, uint num2)public pure returns(uint){
        return num1 / num2 + (num1 % num2 == 0 ? 0 : 1);
    }

}