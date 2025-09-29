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
  address public operator = address(0x2);
  address public stocker1 = address(0x31);
  address public stocker2 = address(0x32);
  address public stocker3 = address(0x33);
  address public alice = address(0x4);
  address public bob = address(0x5);
  address public charlie = address(0x6);

  uint256 constant CYCLE_LENGTH = 7 days;
  uint256 constant PRODUCT_PRICE = 10 * 10 ** 18; // $10
  uint256 constant STOCKER_SHARE_BPS = 2000; // 20%

  event PurchaseTracked(
    address indexed buyer,
    address indexed token,
    uint256 amount,
    uint256 stockerAmount,
    uint256 consumerAmount
  );

  event DistributionExecuted(
    uint256 indexed cycle,
    uint256 buyerCount,
    uint256 timestamp
  );

  function setUp() public {
    vm.startPrank(admin);

    // Deploy mock USDC
    usdc = new MockUSDC();

    // Deploy VendingMachine
    address[] memory acceptedTokens = new address[](1);
    acceptedTokens[0] = address(usdc);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](3);
    products[0] = IVendingMachine.Product('Coca Cola', 'ipfs://coca-cola', STOCKER_SHARE_BPS, stocker1);
    products[1] = IVendingMachine.Product('Pepsi', 'ipfs://pepsi', 1500, stocker2); // 15% stocker share
    products[2] = IVendingMachine.Product('Sprite', 'ipfs://sprite', 2500, stocker3); // 25% stocker share

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

    // Deploy and initialize TreasuryDistributor
    distributor = new TreasuryDistributor();
    distributor.initialize(
      address(voteToken),
      address(vendingMachine),
      CYCLE_LENGTH
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
    
    vm.expectEmit(true, true, false, true);
    emit PurchaseTracked(
      alice,
      address(usdc),
      PRODUCT_PRICE,
      (PRODUCT_PRICE * STOCKER_SHARE_BPS) / 10000,
      PRODUCT_PRICE - (PRODUCT_PRICE * STOCKER_SHARE_BPS) / 10000
    );
    
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    assertEq(distributor.getCurrentBuyerCount(), 1);
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 2 * 10 ** 18); // 20% of $10
    assertEq(distributor.getConsumerRevenue(address(usdc)), 8 * 10 ** 18); // 80% of $10
    assertEq(distributor.getEligibleBalance(alice), PRODUCT_PRICE);
  }

  function testMultiplePurchasesSameBuyer() public {
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 3);
    
    // Purchase 3 items
    vendingMachine.vendFromTrack(0, address(usdc), alice); // 20% stocker share
    vendingMachine.vendFromTrack(1, address(usdc), alice); // 15% stocker share  
    vendingMachine.vendFromTrack(2, address(usdc), alice); // 25% stocker share
    vm.stopPrank();

    assertEq(distributor.getCurrentBuyerCount(), 1); // Still only 1 unique buyer
    
    // Stocker revenue distributed to different stockers
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 2 * 10 ** 18); // 20% of $10
    assertEq(distributor.getStockerRevenue(stocker2, address(usdc)), 15 * 10 ** 17); // 15% of $10
    assertEq(distributor.getStockerRevenue(stocker3, address(usdc)), 25 * 10 ** 17); // 25% of $10
    
    // Consumer revenue: $30 total - $6 stocker = $24
    uint256 totalStockerRevenue = 2 * 10 ** 18 + 15 * 10 ** 17 + 25 * 10 ** 17; // $6 total
    assertEq(distributor.getConsumerRevenue(address(usdc)), 30 * 10 ** 18 - totalStockerRevenue);
    
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

    assertEq(distributor.getCurrentBuyerCount(), 3);
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 6 * 10 ** 18); // 20% of $30 (all from track 0)
    assertEq(distributor.getConsumerRevenue(address(usdc)), 24 * 10 ** 18); // 80% of $30
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

    // Total: $30 revenue, $6 to stocker (20%), $24 to consumers
    // Alice has $20 vote tokens (66.67% of $30 total)
    // Bob has $10 vote tokens (33.33% of $30 total)

    // Move time forward to complete cycle
    vm.warp(block.timestamp + CYCLE_LENGTH);

    // Approve distributor to pull funds from vending machine
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);

    // Record balances before distribution
    uint256 stocker1BalanceBefore = usdc.balanceOf(stocker1);
    uint256 aliceBalanceBefore = usdc.balanceOf(alice);
    uint256 bobBalanceBefore = usdc.balanceOf(bob);

    // Execute distribution
    vm.expectEmit(true, false, false, true);
    emit DistributionExecuted(1, 2, block.timestamp);
    
    distributor.distribute();

    // Check stocker1 received 20% of $30 = $6 (all purchases from track 0)
    assertEq(usdc.balanceOf(stocker1), stocker1BalanceBefore + 6 * 10 ** 18);

    // Check Alice received ~66.67% of $24 = $16
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 16 * 10 ** 18, 1e16); // Allow 0.01 token variance

    // Check Bob received ~33.33% of $24 = $8
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 8 * 10 ** 18, 1e16); // Allow 0.01 token variance

    // Verify new cycle started
    assertEq(distributor.getCurrentCycle(), 2);
    assertEq(distributor.getCurrentBuyerCount(), 0);
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 0);
    assertEq(distributor.getConsumerRevenue(address(usdc)), 0);
  }

  function testDistributionWithDifferentStockerShares() public {
    // Alice buys from track 0 (20% stocker share)
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // Bob buys from track 1 (15% stocker share)
    vm.startPrank(bob);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(1, address(usdc), bob);
    vm.stopPrank();

    // Charlie buys from track 2 (25% stocker share)
    vm.startPrank(charlie);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(2, address(usdc), charlie);
    vm.stopPrank();

    // Stocker revenue per stocker:
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 2 * 10 ** 18); // $2
    assertEq(distributor.getStockerRevenue(stocker2, address(usdc)), 15 * 10 ** 17); // $1.5
    assertEq(distributor.getStockerRevenue(stocker3, address(usdc)), 25 * 10 ** 17); // $2.5
    // Total consumer revenue: $30 - $6 = $24
    assertEq(distributor.getConsumerRevenue(address(usdc)), 24 * 10 ** 18);

    // Move time forward and distribute
    vm.warp(block.timestamp + CYCLE_LENGTH);
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);
    
    distributor.distribute();

    // Each buyer has $10 vote tokens, so each gets 1/3 of consumer revenue ($8)
    assertApproxEqAbs(usdc.balanceOf(alice), 1000 * 10 ** 18 - PRODUCT_PRICE + 8 * 10 ** 18, 1e16);
    assertApproxEqAbs(usdc.balanceOf(bob), 1000 * 10 ** 18 - PRODUCT_PRICE + 8 * 10 ** 18, 1e16);
    assertApproxEqAbs(usdc.balanceOf(charlie), 1000 * 10 ** 18 - PRODUCT_PRICE + 8 * 10 ** 18, 1e16);
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
    distributor.onPurchase(alice, address(usdc), PRODUCT_PRICE, STOCKER_SHARE_BPS, stocker1);
  }

  function testInitializerCanOnlyBeCalledOnce() public {
    // Try to initialize again
    vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
    distributor.initialize(
      address(voteToken),
      address(vendingMachine),
      CYCLE_LENGTH
    );
  }

  function testRestockChangesStockerAndRevShare() public {
    // New operator restocks track 0
    address newOperator = address(0x7);
    vm.startPrank(admin);
    vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), newOperator);
    vm.stopPrank();

    // Before restock, track 0 has stocker1
    IVendingMachine.Track memory trackBefore = vendingMachine.getTrack(0);
    assertEq(trackBefore.product.stockerAddress, stocker1);
    assertEq(trackBefore.product.stockerShareBps, STOCKER_SHARE_BPS); // 20%

    // First, let's buy some items to reduce stock
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE * 5);
    for (uint i = 0; i < 5; i++) {
      vendingMachine.vendFromTrack(0, address(usdc), alice); // Buy 5 items
    }
    vm.stopPrank();
    
    // Stock should now be 95
    assertEq(vendingMachine.getTrackInventory(0), 95);

    // New operator restocks with different share
    uint256 newShareBps = 3000; // 30%
    vm.startPrank(newOperator);
    vendingMachine.restockTrack(0, 5, newShareBps); // Add 5 to get back to 100
    vm.stopPrank();

    // After restock, track 0 should have newOperator as stocker
    IVendingMachine.Track memory trackAfter = vendingMachine.getTrack(0);
    assertEq(trackAfter.product.stockerAddress, newOperator);
    assertEq(trackAfter.product.stockerShareBps, newShareBps);
    assertEq(trackAfter.stock, 100); // Was 95, added 5

    // Now when someone buys from track 0, newOperator should get revenue
    vm.startPrank(alice);
    usdc.approve(address(vendingMachine), PRODUCT_PRICE);
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    // Check that newOperator is tracked for revenue
    // stocker1 got revenue from the first 5 purchases (20% of $50 = $10)
    assertEq(distributor.getStockerRevenue(stocker1, address(usdc)), 10 * 10 ** 18); 
    // newOperator gets revenue from the last purchase (30% of $10 = $3)
    assertEq(distributor.getStockerRevenue(newOperator, address(usdc)), 3 * 10 ** 18);
    // Total consumer revenue: 80% of $50 + 70% of $10 = $40 + $7 = $47
    assertEq(distributor.getConsumerRevenue(address(usdc)), 47 * 10 ** 18);
  }
}