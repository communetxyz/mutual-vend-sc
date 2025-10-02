// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import {TreasuryDistributor} from '../../src/contracts/TreasuryDistributor.sol';
import {VendingMachine} from '../../src/contracts/VendingMachine.sol';
import {VoteToken} from '../../src/contracts/VoteToken.sol';
import {ITreasuryDistributor} from '../../src/interfaces/ITreasuryDistributor.sol';
import {IVendingMachine} from '../../src/interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockUSDC is ERC20 {
  constructor() ERC20('Mock USDC', 'USDC') {
    _mint(msg.sender, 1000000 * 10 ** 18);
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract TreasuryDistributorTest is Test {
  TreasuryDistributor public distributor;
  VendingMachine public vendingMachine;
  VoteToken public voteToken;
  MockUSDC public usdc;

  address public admin = address(0x1);
  address public alice = address(0x4);
  address public bob = address(0x5);
  address public charlie = address(0x6);

  uint256 constant CYCLE_LENGTH = 7 days;
  uint256 constant PRODUCT_PRICE = 10 * 10 ** 18; // $10
  uint256 constant DISTRIBUTION_PERCENTAGE = 8000; // 80%

  event PurchaseTracked(
    address indexed buyer,
    address indexed token,
    uint256 amount,
    uint256 distributedAmount,
    uint256 retainedAmount
  );

  event DistributionExecuted(
    uint256 indexed cycle,
    uint256 buyerCount,
    uint256 timestamp
  );

  event DistributionPercentageUpdated(
    uint256 oldPercentage,
    uint256 newPercentage
  );

  event RetainedRevenueWithdrawn(
    address indexed token,
    uint256 amount,
    address indexed recipient
  );

  function setUp() public {
    vm.startPrank(admin);

    // Deploy mock USDC
    usdc = new MockUSDC();

    // Deploy VendingMachine
    address[] memory acceptedTokens = new address[](1);
    acceptedTokens[0] = address(usdc);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](3);
    products[0] = IVendingMachine.Product('Coca Cola', 'ipfs://coca-cola');
    products[1] = IVendingMachine.Product('Pepsi', 'ipfs://pepsi');
    products[2] = IVendingMachine.Product('Sprite', 'ipfs://sprite');

    uint256[] memory stocks = new uint256[](3);
    stocks[0] = 100;
    stocks[1] = 100;
    stocks[2] = 100;

    uint256[] memory prices = new uint256[](3);
    prices[0] = PRODUCT_PRICE;
    prices[1] = PRODUCT_PRICE;
    prices[2] = PRODUCT_PRICE;

    vendingMachine = new VendingMachine(
      3, // num tracks
      100, // max stock per track
      'Vote Token',
      'VOTE',
      acceptedTokens,
      products,
      stocks,
      prices
    );

    voteToken = vendingMachine.voteToken();

    // Deploy and initialize TreasuryDistributor with 80% distribution percentage
    distributor = new TreasuryDistributor();
    distributor.initialize(
      address(voteToken),
      address(vendingMachine),
      CYCLE_LENGTH,
      DISTRIBUTION_PERCENTAGE // 80% distributed, 20% retained
    );

    // Configure VendingMachine
    vendingMachine.setTreasuryDistributor(address(distributor));
    vendingMachine.grantRole(vendingMachine.TREASURY_ROLE(), address(distributor));

    // Distribute USDC to buyers
    usdc.transfer(alice, 1000 * 10 ** 18);
    usdc.transfer(bob, 1000 * 10 ** 18);
    usdc.transfer(charlie, 1000 * 10 ** 18);

    vm.stopPrank();
  }

  function testPurchaseTracking() public {
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    
    // 80% distributable, 20% retained
    uint256 distributableAmount = (PRODUCT_PRICE * DISTRIBUTION_PERCENTAGE) / 10000;
    uint256 retainedAmount = PRODUCT_PRICE - distributableAmount;
    
    vm.expectEmit(true, true, false, true);
    emit PurchaseTracked(
      alice,
      address(usdc),
      PRODUCT_PRICE,
      distributableAmount,
      retainedAmount
    );
    
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    assertEq(distributor.getCurrentBuyerCount(), 1);
    assertEq(distributor.getDistributableRevenue(address(usdc)), distributableAmount);
    assertEq(distributor.getRetainedRevenue(address(usdc)), retainedAmount);
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE);
  }

  function testMultiplePurchasesSameBuyer() public {
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 3);
    
    // Purchase 3 items
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vendingMachine.vendFromTrack(1, address(usdc), alice);
    vendingMachine.vendFromTrack(2, address(usdc), alice);
    vm.stopPrank();

    uint256 totalRevenue = PRODUCT_PRICE * 3;
    uint256 distributableAmount = (totalRevenue * DISTRIBUTION_PERCENTAGE) / 10000;
    uint256 retainedAmount = totalRevenue - distributableAmount;

    assertEq(distributor.getCurrentBuyerCount(), 1); // Still only 1 unique buyer
    assertEq(distributor.getDistributableRevenue(address(usdc)), distributableAmount);
    assertEq(distributor.getRetainedRevenue(address(usdc)), retainedAmount);
    
    // Alice should have $30 worth of vote tokens
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE * 3);
  }

  function testMultipleBuyers() public {
    // Alice buys
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // Bob buys
    vm.startPrank(bob);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), bob);
    vm.stopPrank();

    // Charlie buys
    vm.startPrank(charlie);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), charlie);
    vm.stopPrank();

    uint256 totalRevenue = 30 * 10 ** 18;
    uint256 distributableAmount = (totalRevenue * DISTRIBUTION_PERCENTAGE) / 10000;
    uint256 retainedAmount = totalRevenue - distributableAmount;

    assertEq(distributor.getCurrentBuyerCount(), 3);
    assertEq(distributor.getDistributableRevenue(address(usdc)), distributableAmount);
    assertEq(distributor.getRetainedRevenue(address(usdc)), retainedAmount);
  }

  function testDistributionBeforeCycleComplete() public {
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // Try to distribute before cycle is complete
    vm.expectRevert(ITreasuryDistributor.CycleNotComplete.selector);
    distributor.distribute();
  }

  function testSuccessfulDistribution() public {
    // Make purchases
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 2);
    vendingMachine.vendFromTrack(0, address(usdc), alice); // $10 purchase, Alice gets $10 vote tokens
    vendingMachine.vendFromTrack(0, address(usdc), alice); // Another $10, Alice now has $20 vote tokens
    vm.stopPrank();

    vm.startPrank(bob);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), bob); // $10 purchase, Bob gets $10 vote tokens
    vm.stopPrank();

    // Total: $30 revenue
    // Distributable: $24 (80% of $30)
    // Retained: $6 (20% of $30)
    // Alice has $20 vote tokens (66.67% of $30 total)
    // Bob has $10 vote tokens (33.33% of $30 total)

    // Move time forward to complete cycle
    vm.warp(block.timestamp + CYCLE_LENGTH);

    // Approve distributor to pull funds from vending machine
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);

    // Record balances before distribution
    uint256 aliceBalanceBefore = usdc.balanceOf(alice);
    uint256 bobBalanceBefore = usdc.balanceOf(bob);

    // Execute distribution
    vm.expectEmit(true, false, false, true);
    emit DistributionExecuted(1, 2, block.timestamp);
    
    distributor.distribute();

    // Check Alice received ~66.67% of $24 = $16
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 16 * 10 ** 18, 1e16);

    // Check Bob received ~33.33% of $24 = $8
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 8 * 10 ** 18, 1e16);

    // Check that $6 remains as retained revenue
    assertEq(distributor.getRetainedRevenue(address(usdc)), 6 * 10 ** 18);

    // Verify new cycle started
    assertEq(distributor.getCurrentCycle(), 2);
    assertEq(distributor.getCurrentBuyerCount(), 0);
    assertEq(distributor.getDistributableRevenue(address(usdc)), 0);
  }

  function testGetTimeUntilNextDistribution() public {
    uint256 timeUntil = distributor.getTimeUntilNextDistribution();
    assertEq(timeUntil, CYCLE_LENGTH);

    // Move time forward
    vm.warp(block.timestamp + CYCLE_LENGTH / 2);
    timeUntil = distributor.getTimeUntilNextDistribution();
    assertEq(timeUntil, CYCLE_LENGTH / 2);

    // Move to end of cycle
    vm.warp(block.timestamp + CYCLE_LENGTH / 2);
    timeUntil = distributor.getTimeUntilNextDistribution();
    assertEq(timeUntil, 0);
  }

  function testOnlyVendingMachineCanCallOnPurchase() public {
    vm.expectRevert(ITreasuryDistributor.NotAuthorized.selector);
    distributor.onPurchase(alice, address(usdc), PRODUCT_PRICE);
  }

  function testInitializerCanOnlyBeCalledOnce() public {
    // Try to initialize again
    vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
    distributor.initialize(
      address(voteToken),
      address(vendingMachine),
      CYCLE_LENGTH,
      DISTRIBUTION_PERCENTAGE
    );
  }

  function testPurchaseWithNoRecipient() public {
    // Purchase with no recipient (address(0))
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    
    // Vend with no recipient (no vote tokens minted, no revenue sharing)
    vendingMachine.vendFromTrack(0, address(usdc), address(0));
    vm.stopPrank();

    // Check that no buyer was tracked
    assertEq(distributor.getCurrentBuyerCount(), 0);
    
    // No revenue should be tracked at all (onPurchase not called)
    assertEq(distributor.getDistributableRevenue(address(usdc)), 0);
    assertEq(distributor.getRetainedRevenue(address(usdc)), 0);
    
    // No eligible balance for address(0)
    assertEq(distributor.getEligibleBalance(address(0)), 0);
    
    // No vote tokens minted
    assertEq(voteToken.totalSupply(), 0);
  }

  function testMixedPurchasesWithAndWithoutRecipient() public {
    // Alice buys with recipient
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 2);
    vendingMachine.vendFromTrack(0, address(usdc), alice); // With recipient
    vendingMachine.vendFromTrack(0, address(usdc), address(0)); // Without recipient (no revenue sharing)
    vm.stopPrank();

    // Bob buys with recipient
    vm.startPrank(bob);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), bob);
    vm.stopPrank();

    // Only 2 buyers tracked (alice and bob)
    assertEq(distributor.getCurrentBuyerCount(), 2);
    
    // Revenue only from purchases with recipients (2 out of 3)
    uint256 totalRevenue = 20 * 10 ** 18; // $20 from 2 purchases
    uint256 distributableAmount = (totalRevenue * DISTRIBUTION_PERCENTAGE) / 10000;
    uint256 retainedAmount = totalRevenue - distributableAmount;
    
    assertEq(distributor.getDistributableRevenue(address(usdc)), distributableAmount);
    assertEq(distributor.getRetainedRevenue(address(usdc)), retainedAmount);
    
    // Move time forward and distribute
    vm.warp(block.timestamp + CYCLE_LENGTH);
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);
    
    uint256 aliceBalanceBefore = usdc.balanceOf(alice);
    uint256 bobBalanceBefore = usdc.balanceOf(bob);
    
    distributor.distribute();
    
    // Alice and Bob split the distributable revenue
    // Both have $10 vote tokens (50/50 split)
    // Distributable: $16 (80% of $20)
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 8 * 10 ** 18, 1e16);
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 8 * 10 ** 18, 1e16);
    
    // The entire $10 from the no-recipient purchase stays in vending machine
    // (no revenue sharing at all for that purchase)
  }

  function testMultiplePurchasesSameBuyerSameCycle() public {
    // This test specifically verifies that multiple purchases by the same buyer
    // in the same cycle are properly accumulated (addressing review comment)
    
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 3);
    
    // First purchase - Alice gets $10 vote tokens
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    assertEq(voteToken.balanceOf(alice), PRODUCT_PRICE);
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE);
    
    // Second purchase - Alice gets another $10, total $20
    vendingMachine.vendFromTrack(1, address(usdc), alice);
    assertEq(voteToken.balanceOf(alice), PRODUCT_PRICE * 2);
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE * 2); // Should be cumulative
    
    // Third purchase - Alice gets another $10, total $30
    vendingMachine.vendFromTrack(2, address(usdc), alice);
    assertEq(voteToken.balanceOf(alice), PRODUCT_PRICE * 3);
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE * 3); // Should be cumulative
    
    vm.stopPrank();
    
    // Bob makes one purchase
    vm.startPrank(bob);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), bob);
    vm.stopPrank();
    
    // Move time forward and distribute
    vm.warp(block.timestamp + CYCLE_LENGTH);
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);
    
    uint256 aliceBalanceBefore = usdc.balanceOf(alice);
    uint256 bobBalanceBefore = usdc.balanceOf(bob);
    
    distributor.distribute();
    
    // Total revenue: $40 ($30 from Alice, $10 from Bob)
    // Distributable: $32 (80% of $40)
    // Alice should get 75% (30/40) of $32 = $24
    // Bob should get 25% (10/40) of $32 = $8
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 24 * 10 ** 18, 1e16);
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 8 * 10 ** 18, 1e16);
  }

  function testSetDistributionPercentage() public {
    // Only owner can change distribution percentage
    vm.expectRevert(ITreasuryDistributor.NotAuthorized.selector);
    vm.prank(alice);
    distributor.setDistributionPercentage(5000);

    // Owner can change distribution percentage
    vm.prank(admin);
    vm.expectEmit(false, false, false, true);
    emit DistributionPercentageUpdated(8000, 5000);
    distributor.setDistributionPercentage(5000);
    
    assertEq(distributor.getDistributionPercentage(), 5000);

    // Test with new percentage
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // Should be 50/50 split now
    assertEq(distributor.getDistributableRevenue(address(usdc)), 5 * 10 ** 18);
    assertEq(distributor.getRetainedRevenue(address(usdc)), 5 * 10 ** 18);
  }

  function testWithdrawRetainedRevenue() public {
    // Make some purchases to accumulate retained revenue
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 2);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vendingMachine.vendFromTrack(1, address(usdc), alice);
    vm.stopPrank();

    // Total revenue: $20
    // Retained: $4 (20% of $20)
    assertEq(distributor.getRetainedRevenue(address(usdc)), 4 * 10 ** 18);

    // Only owner can withdraw
    vm.expectRevert(ITreasuryDistributor.NotAuthorized.selector);
    vm.prank(alice);
    distributor.withdrawRetainedRevenue(address(usdc), alice);

    // Owner withdraws retained revenue
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);

    uint256 adminBalanceBefore = usdc.balanceOf(admin);
    
    vm.prank(admin);
    vm.expectEmit(true, false, false, true);
    emit RetainedRevenueWithdrawn(address(usdc), 4 * 10 ** 18, admin);
    distributor.withdrawRetainedRevenue(address(usdc), admin);

    // Check admin received the retained revenue
    assertEq(usdc.balanceOf(admin), adminBalanceBefore + 4 * 10 ** 18);
    
    // Retained revenue should be zero now
    assertEq(distributor.getRetainedRevenue(address(usdc)), 0);

    // Cannot withdraw again (no revenue to withdraw)
    vm.expectRevert(ITreasuryDistributor.NoRevenueToWithdraw.selector);
    vm.prank(admin);
    distributor.withdrawRetainedRevenue(address(usdc), admin);
  }

  function testInvalidDistributionPercentage() public {
    // Try to set percentage > 100%
    vm.prank(admin);
    vm.expectRevert(ITreasuryDistributor.InvalidPercentage.selector);
    distributor.setDistributionPercentage(10001);
  }

  function testZeroDistributionPercentage() public {
    // Set to 0% distribution (100% retained)
    vm.prank(admin);
    distributor.setDistributionPercentage(0);

    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // All revenue should be retained
    assertEq(distributor.getDistributableRevenue(address(usdc)), 0);
    assertEq(distributor.getRetainedRevenue(address(usdc)), PRODUCT_PRICE);

    // Distribution should work but distribute nothing
    vm.warp(block.timestamp + CYCLE_LENGTH);
    distributor.distribute();
    
    // Alice started with 1000e18, spent 10e18 on purchase, should still have 990e18 (no distribution)
    assertEq(usdc.balanceOf(alice), 990 * 10 ** 18); // No distribution
  }

  function testFullDistributionPercentage() public {
    // Set to 100% distribution (0% retained)
    vm.prank(admin);
    distributor.setDistributionPercentage(10000);

    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // All revenue should be distributable
    assertEq(distributor.getDistributableRevenue(address(usdc)), PRODUCT_PRICE);
    assertEq(distributor.getRetainedRevenue(address(usdc)), 0);
  }
}