// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

contract CCNCarnival {
    //number for operating days
    enum OperatingDuration { FRIDAY_ONLY, FRIDAY_SATURDAY, ALL_THREE_DAYS }
    
    //Struct for stall information
    struct Stall {
        uint256 stallId;
        string stallName;
        address owner;           
        OperatingDuration duration;
        bool isActive;
        uint256 totalEarnings;
        bool hasWithdrawn;      //track if owner has withdrawn funds
        uint256 totalRating; // 1-5 scale for ratings
        uint256 ratingCount;
    }
    
    // Struct for products 
    struct Product {
        uint256 productId;
        uint256 stallId;
        string name;
        uint256 price;
    }
    
    // Struct for payments tracking
    struct Payment {
        address payer;
        uint256 stallId;
        uint256 amount;
        uint256 timestamp;
        bool refunded;
    }
    
    //variables
    address public admin;
    uint256 public nextStallId = 1;
    uint256 public nextProductId = 1;
    uint256 public nextPaymentId = 1;
    
    // Current day of carnival ( 1=Friday, 2=Saturday, 3=Sunday)
    uint256 public currentCarnivalDay = 1;
    bool public carnivalEnded = false;
    
    // Mappings
    mapping(uint256 => Stall) public stalls;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Payment) public payments;
    mapping(address => uint256[]) public stallOwnerStalls; //track stalls per owner
    mapping(uint256 => uint256[]) public stallPayments;   //track payments per stall
    
    
    uint256[] public stallIds;
    
    //Events
    event StallRegistered(uint256 indexed stallId, string stallName, address indexed owner, OperatingDuration duration);
    event PaymentMade(uint256 indexed paymentId, address indexed payer, uint256 indexed stallId, uint256 amount);
    event RefundIssued(uint256 indexed paymentId, uint256 amount);
    event FundsWithdrawn(uint256 indexed stallId, address indexed owner, uint256 amount);
    event CarnivalDayChanged(uint256 newDay);
    
    //Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }
    
    modifier onlyStallOwner(uint256 _stallId) {
        require(stalls[_stallId].owner == msg.sender, "Only stall owner can perform this action");
        _;
    }
    
    modifier stallExists(uint256 _stallId) {
        require(stalls[_stallId].stallId != 0, "Stall does not exist");
        _;
    }
    
    modifier carnivalActive() {
        require(!carnivalEnded, "Carnival has ended");
        _;
    }
    
    constructor() {
        admin = msg.sender;
    }
    
    // Admin functions
    function registerStall(
        string memory _stallName, 
        address _owner, 
        OperatingDuration _duration
    ) public onlyAdmin carnivalActive {
        require(bytes(_stallName).length > 0, "Stall name cannot be empty");
        require(_owner != address(0), "Invalid owner address");
        
        Stall memory newStall = Stall({
            stallId: nextStallId,
            stallName: _stallName,
            owner: _owner,
            duration: _duration,
            isActive: true,
            totalEarnings: 0,
            hasWithdrawn: false,
            totalRating: 0, 
            ratingCount:0
        });
        
        stalls[nextStallId] = newStall;
        stallIds.push(nextStallId);
        stallOwnerStalls[_owner].push(nextStallId);
        
        emit StallRegistered(nextStallId, _stallName, _owner, _duration);
        nextStallId++;
    }
    
    function setCarnivalDay(uint256 _day) public onlyAdmin {
        require(_day >= 1 && _day <= 3, "Day must be 1 (Friday), 2 (Saturday), or 3 (Sunday)");
        currentCarnivalDay = _day;
        emit CarnivalDayChanged(_day);
    }
    
    function endCarnival() public onlyAdmin {
        carnivalEnded = true;
    }
    
    function makePayment(uint256 _productId) public payable carnivalActive {
        Product memory product = products[_productId];
        require(product.productId != 0, "Product does not exist");
        require(isStallOperating(product.stallId), "Stall is not operating today");
        require(product.price > 0, "Product price must be greater than 0");

        uint256 price = discountedPrice(_productId);

        // If payment is too low
        if (msg.value < price) {
            revert(string(abi.encodePacked("Not enough money, please pay the total amount: ", uint2str(price))));
        }

        // If payment is too high (refund the difference)
        if (msg.value > price) {
            uint256 refundAmount = msg.value - price;
           (bool success, ) = msg.sender.call{value: refundAmount}("");
           require(success, "Refund failed");
        }

        // Record payment with the correct price
        payments[nextPaymentId] = Payment({
            payer: msg.sender,
            stallId: product.stallId,
            amount: price, // store actual price, not overpaid amount
            timestamp: block.timestamp,
            refunded: false
        });

        stalls[product.stallId].totalEarnings += price;
        stallPayments[product.stallId].push(nextPaymentId);

        emit PaymentMade(nextPaymentId, msg.sender, product.stallId, price);
        nextPaymentId++;
    }

    //convert uint to string to display price in message 
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 temp = _i;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_i != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_i % 10)));
            _i /= 10;
        }
        return string(buffer);
    }



    
    // Stall owner functions
    function issueRefund(uint256 _paymentId) public {
        require(payments[_paymentId].payer != address(0), "Payment does not exist");
        require(!payments[_paymentId].refunded, "Payment already refunded");
        require(stalls[payments[_paymentId].stallId].owner == msg.sender, "Only stall owner can issue refunds");
        
        Payment storage payment = payments[_paymentId];
        uint256 refundAmount = payment.amount;
        
        // refunded
        payment.refunded = true;
        
        //deduct stall earnings
        stalls[payment.stallId].totalEarnings -= refundAmount;
        
        // Send refund
        payable(payment.payer).transfer(refundAmount);
        
        emit RefundIssued(_paymentId, refundAmount);
    }
    
    function withdrawFunds(uint256 _stallId) public onlyStallOwner(_stallId) stallExists(_stallId) {
        require(carnivalEnded || !isStallOperating(_stallId), "Can only withdraw when stall operation is complete");
        require(!stalls[_stallId].hasWithdrawn, "Funds already withdrawn");
        require(stalls[_stallId].totalEarnings > 0, "No funds to withdraw");
        
        uint256 amount = stalls[_stallId].totalEarnings;
        stalls[_stallId].hasWithdrawn = true;
        
        payable(msg.sender).transfer(amount);
        
        emit FundsWithdrawn(_stallId, msg.sender, amount);
    }
    
    function isStallOperating(uint256 _stallId) public view stallExists(_stallId) returns (bool) {
        if (!stalls[_stallId].isActive) return false;
        
        OperatingDuration duration = stalls[_stallId].duration;
        
        if (duration == OperatingDuration.FRIDAY_ONLY) {
            return currentCarnivalDay == 1;
        } else if (duration == OperatingDuration.FRIDAY_SATURDAY) {
            return currentCarnivalDay == 1 || currentCarnivalDay == 2;
        } else { // all 3 days
            return currentCarnivalDay >= 1 && currentCarnivalDay <= 3;
        }
    }
    
    // Get functions
    function getStallInfo(uint256 _stallId) public view stallExists(_stallId) returns (Stall memory) {
        return stalls[_stallId];
    }
    
    function getStallsByOwner(address _owner) public view returns (uint256[] memory) {
        return stallOwnerStalls[_owner];
    }
    
    function getStallPayments(uint256 _stallId) public view returns (uint256[] memory) {
        return stallPayments[_stallId];
    }
    
    function getAllStalls() public view returns (uint256[] memory) {
        return stallIds;
    }
    
    //product management to track specific items
    function addProduct(uint256 _stallId, string memory _name, uint256 _price) 
        public onlyStallOwner(_stallId) stallExists(_stallId) 
    {
        require(bytes(_name).length > 0, "Product name cannot be empty");
        require(_price > 0, "Price must be greater than 0");
        
        products[nextProductId] = Product({
            productId: nextProductId,
            stallId: _stallId,
            name: _name,
            price: _price
        });
        
        nextProductId++;
    }

    //30% discount for stores on the last day 
    function discountedPrice(uint256 _productId) public view returns (uint256) {
        uint256 price = products[_productId].price;
        if (currentCarnivalDay == 3){
            return price * 70 / 100; //30% discount
            } else {
                return price;
                }
    }

    //store ratings
    function rateStall(uint256 _stallId, uint256 _rating) public {
       require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
       stalls[_stallId].totalRating += _rating;
       stalls[_stallId].ratingCount++;
    }

    function getAverageRating(uint256 _stallId) public view returns (uint256) {
        if (stalls[_stallId].ratingCount == 0) return 0;
        return stalls[_stallId].totalRating / stalls[_stallId].ratingCount;
        }


    
}