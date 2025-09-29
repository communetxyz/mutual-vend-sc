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
      0, // No stocker amount
      PRODUCT_PRICE // All revenue goes to consumers
    );
    
    vendingMachine.vendFromTrack(0, address(usdc), alice);
    vm.stopPrank();

    assertEq(distributor.getCurrentBuyerCount(), 1);
    assertEq(distributor.getStockerRevenue(address(usdc)), 0); // No stocker revenue
    assertEq(distributor.getConsumerRevenue(address(usdc)), PRODUCT_PRICE); // All to consumers
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

    assertEq(distributor.getCurrentBuyerCount(), 1); // Still only 1 unique buyer
    assertEq(distributor.getConsumerRevenue(address(usdc)), PRODUCT_PRICE * 3); // All to consumers
    
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
    assertEq(distributor.getConsumerRevenue(address(usdc)), 30 * 10 ** 18); // $30 total
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

    // Check Alice received ~66.67% of $30 = $20
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 20 * 10 ** 18, 1e16);

    // Check Bob received ~33.33% of $30 = $10
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 10 * 10 ** 18, 1e16);

    // Verify new cycle started
    assertEq(distributor.getCurrentCycle(), 2);
    assertEq(distributor.getCurrentBuyerCount(), 0);
    assertEq(distributor.getConsumerRevenue(address(usdc)), 0);
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
      CYCLE_LENGTH
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
    assertEq(distributor.getStockerRevenue(address(usdc)), 0);
    assertEq(distributor.getConsumerRevenue(address(usdc)), 0);
    
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
    assertEq(distributor.getConsumerRevenue(address(usdc)), 20 * 10 ** 18); // $20 (2 purchases)
    
    // Move time forward and distribute
    vm.warp(block.timestamp + CYCLE_LENGTH);
    vm.prank(address(vendingMachine));
    usdc.approve(address(distributor), type(uint256).max);
    
    uint256 aliceBalanceBefore = usdc.balanceOf(alice);
    uint256 bobBalanceBefore = usdc.balanceOf(bob);
    
    distributor.distribute();
    
    // Alice and Bob split the $20 revenue
    // Alice has $10 vote tokens, Bob has $10 vote tokens (50/50 split)
    assertApproxEqAbs(usdc.balanceOf(alice), aliceBalanceBefore + 10 * 10 ** 18, 1e16);
    assertApproxEqAbs(usdc.balanceOf(bob), bobBalanceBefore + 10 * 10 ** 18, 1e16);
    
    // The entire $10 from the no-recipient purchase stays in vending machine
    // (no revenue sharing at all for that purchase)
  }
}