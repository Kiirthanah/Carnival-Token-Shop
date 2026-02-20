// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.4.22 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
import "remix_accounts.sol";
import "../register_store.sol";

//test case for admin

// File name has to end with '_test.sol'
contract CCNCarnivalTest {
    
    CCNCarnival carnival;
    address admin;
    address stallOwner1;
    address stallOwner2;

    /// 'beforeAll' runs before all other tests
    function beforeAll() public {
        // Deploy the contract and set up test accounts
        carnival = new CCNCarnival();
        admin = TestsAccounts.getAccount(0); // Admin account
        stallOwner1 = TestsAccounts.getAccount(1); // Stall owner 1
        stallOwner2 = TestsAccounts.getAccount(2); // Stall owner 2
    }

    /// Test 1: Register Store (Stall)
    function testRegisterStall() public {
        // Test registering a stall as admin
        carnival.registerStall("Drinks Stall", stallOwner1, CCNCarnival.OperatingDuration.ALL_THREE_DAYS);
        
        // Verify the stall was registered correctly
        CCNCarnival.Stall memory stall = carnival.getStallInfo(1);
        Assert.equal(stall.stallId, 1, "Stall ID should be 1");
        Assert.equal(stall.stallName, "Drinks Stall", "Stall name should be Drinks Stall");
        Assert.equal(stall.owner, stallOwner1, "Stall owner should be correct");
        Assert.equal(uint(stall.duration), uint(CCNCarnival.OperatingDuration.ALL_THREE_DAYS), "Duration should be ALL_THREE_DAYS");
        Assert.ok(stall.isActive, "Stall should be active");
        Assert.equal(stall.totalEarnings, 0, "Initial earnings should be 0");
        Assert.ok(!stall.hasWithdrawn, "Should not have withdrawn initially");
    }

    function testRegisterMultipleStalls() public {
        // Register another stall
        carnival.registerStall("Cookies", stallOwner2, CCNCarnival.OperatingDuration.FRIDAY_SATURDAY);
        
        // Verify the second stall
        CCNCarnival.Stall memory stall2 = carnival.getStallInfo(2);
        Assert.equal(stall2.stallId, 2, "Second stall ID should be 2");
        Assert.equal(stall2.stallName, "Cookies", "Second stall name should be Cookies");
        Assert.equal(stall2.owner, stallOwner2, "Second stall owner should be correct");
        Assert.equal(uint(stall2.duration), uint(CCNCarnival.OperatingDuration.FRIDAY_SATURDAY), "Duration should be FRIDAY_SATURDAY");
    }

    /// Test 2: End Carnival
    function testEndCarnival() public {
        // End the carnival
        carnival.endCarnival();
        
        // Verify carnival has ended
        Assert.ok(carnival.carnivalEnded(), "Carnival should be ended");
    }


}