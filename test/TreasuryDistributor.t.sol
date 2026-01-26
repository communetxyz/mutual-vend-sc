// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TreasuryDistributor} from '../src/contracts/TreasuryDistributor.sol';
import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {VoteToken} from '../src/contracts/VoteToken.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {ERC20Mock} from './mocks/ERC20Mock.sol';
import {Test} from 'forge-std/Test.sol';

contract TreasuryDistributorTest is Test {
  VendingMachine vendingMachine;
  TreasuryDistributor treasuryDistributor;
  VoteToken voteToken;
  ERC20Mock usdc;
  ERC20Mock usdt;
  ERC20Mock dai;

  address admin = address(this);
  address buyer1 = address(0x1);
  address buyer2 = address(0x2);
  address buyer3 = address(0x3);
  address operator = address(0x4);

  uint256 constant PRICE = 1e18; // $1
  uint256 constant INITIAL_BALANCE = 1000e18;

  event PurchaseTracked(address indexed buyer, uint256 eligibleAmount, uint256 totalEligible);
  event DividendDistributed(address indexed recipient, address indexed token, uint256 amount);
  event CycleCompleted(uint256 indexed cycle, uint256 totalRevenue, uint256 buyerCount);
  event NewCycleStarted(uint256 indexed cycle, uint256 timestamp);

  function setUp() public {
    // Deploy mock tokens
    usdc = new ERC20Mock('USDC', 'USDC', 18);
    usdt = new ERC20Mock('USDT', 'USDT', 18);
    dai = new ERC20Mock('DAI', 'DAI', 18);

    // Deploy vending machine
    address[] memory acceptedTokens = new address[](3);
    acceptedTokens[0] = address(usdc);
    acceptedTokens[1] = address(usdt);
    acceptedTokens[2] = address(dai);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](3);
    products[0] = IVendingMachine.Product('Cola', 'ipfs://cola');
    products[1] = IVendingMachine.Product('Chips', 'ipfs://chips');
    products[2] = IVendingMachine.Product('Candy', 'ipfs://candy');

    uint256[] memory stocks = new uint256[](3);
    stocks[0] = 100;
    stocks[1] = 100;
    stocks[2] = 100;

    uint256[] memory prices = new uint256[](3);
    prices[0] = PRICE;
    prices[1] = PRICE;
    prices[2] = PRICE;

    vendingMachine = new VendingMachine(
      3, // num tracks
      1000, // max stock per track
      'Vending Vote Token',
      'VVT',
      acceptedTokens,
      products,
      stocks,
      prices,
      address(0) // no treasury distributor initially
    );

    voteToken = vendingMachine.voteToken();

    // Deploy treasury distributor
    treasuryDistributor = new TreasuryDistributor(address(vendingMachine));

    // Set treasury distributor in vending machine
    vendingMachine.setTreasuryDistributor(address(treasuryDistributor));

    // Grant operator role
    vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), operator);

    // Mint tokens to buyers
    usdc.mint(buyer1, INITIAL_BALANCE);
    usdc.mint(buyer2, INITIAL_BALANCE);
    usdc.mint(buyer3, INITIAL_BALANCE);
    usdt.mint(buyer1, INITIAL_BALANCE);
    usdt.mint(buyer2, INITIAL_BALANCE);
    dai.mint(buyer3, INITIAL_BALANCE);

    // Approve vending machine
    vm.prank(buyer1);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vm.prank(buyer1);
    usdt.approve(address(vendingMachine), type(uint256).max);

    vm.prank(buyer2);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vm.prank(buyer2);
    usdt.approve(address(vendingMachine), type(uint256).max);

    vm.prank(buyer3);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vm.prank(buyer3);
    dai.approve(address(vendingMachine), type(uint256).max);
  }

  function test_PurchaseTracking() public {
    // Buyer1 makes a purchase
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    // Check tracking
    assertEq(treasuryDistributor.getBuyerEligibleBalance(buyer1), PRICE);
    assertEq(treasuryDistributor.totalEligible(), PRICE);

    address[] memory buyers = treasuryDistributor.getCurrentBuyers();
    assertEq(buyers.length, 1);
    assertEq(buyers[0], buyer1);

    // Buyer2 makes a purchase
    vm.prank(buyer2);
    vendingMachine.vendFromTrack(1, address(usdc), buyer2);

    assertEq(treasuryDistributor.getBuyerEligibleBalance(buyer2), PRICE);
    assertEq(treasuryDistributor.totalEligible(), PRICE * 2);

    buyers = treasuryDistributor.getCurrentBuyers();
    assertEq(buyers.length, 2);
  }

  function test_MultiplePurchasesSameBuyer() public {
    // Buyer1 makes first purchase
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    assertEq(treasuryDistributor.getBuyerEligibleBalance(buyer1), PRICE);
    assertEq(treasuryDistributor.totalEligible(), PRICE);

    // Buyer1 makes second purchase
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(1, address(usdt), buyer1);

    // Should have 2x the price as eligible balance
    assertEq(treasuryDistributor.getBuyerEligibleBalance(buyer1), PRICE * 2);
    assertEq(treasuryDistributor.totalEligible(), PRICE * 2);

    // Should still only be 1 buyer in array
    address[] memory buyers = treasuryDistributor.getCurrentBuyers();
    assertEq(buyers.length, 1);
    assertEq(buyers[0], buyer1);
  }

  function test_RevenueDistribution() public {
    // Make purchases
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1); // 1 VVT

    vm.prank(buyer2);
    vendingMachine.vendFromTrack(1, address(usdc), buyer2); // 1 VVT

    vm.prank(buyer2);
    vendingMachine.vendFromTrack(2, address(usdt), buyer2); // 1 VVT (total 2 VVT)

    vm.prank(buyer3);
    vendingMachine.vendFromTrack(0, address(dai), buyer3); // 1 VVT

    // Total: buyer1 = 1 VVT, buyer2 = 2 VVT, buyer3 = 1 VVT
    // Total revenue: 2 USDC, 1 USDT, 1 DAI

    // Fast forward to end of cycle
    vm.warp(block.timestamp + 30 days + 1);

    // Check cycle is complete
    assertTrue(treasuryDistributor.isCycleComplete());

    // Record balances before distribution
    uint256 buyer1UsdcBefore = usdc.balanceOf(buyer1);
    uint256 buyer2UsdcBefore = usdc.balanceOf(buyer2);
    uint256 buyer2UsdtBefore = usdt.balanceOf(buyer2);

    // Distribute revenue
    vm.expectEmit(true, false, false, true);
    emit CycleCompleted(0, 4e18, 3); // 4 tokens total revenue, 3 buyers
    treasuryDistributor.distributeMonthlyRevenue();

    // Check distributions
    // buyer1 has 25% (1/4 VVT)
    assertEq(usdc.balanceOf(buyer1) - buyer1UsdcBefore, 2e18 * 25 / 100); // 0.5 USDC
    assertEq(usdt.balanceOf(buyer1), INITIAL_BALANCE + (1e18 * 25 / 100)); // Original + 0.25 USDT from distribution
    assertEq(dai.balanceOf(buyer1), 1e18 * 25 / 100); // 0.25 DAI

    // buyer2 has 50% (2/4 VVT)
    assertEq(usdc.balanceOf(buyer2) - buyer2UsdcBefore, 2e18 * 50 / 100); // 1 USDC
    assertEq(usdt.balanceOf(buyer2) - buyer2UsdtBefore, 1e18 * 50 / 100); // 0.5 USDT
    assertEq(dai.balanceOf(buyer2), 1e18 * 50 / 100); // 0.5 DAI

    // buyer3 has 25% (1/4 VVT)
    assertEq(usdc.balanceOf(buyer3), INITIAL_BALANCE + (2e18 * 25 / 100)); // Original + 0.5 USDC from distribution
    assertEq(usdt.balanceOf(buyer3), 1e18 * 25 / 100); // 0.25 USDT
    assertEq(dai.balanceOf(buyer3), INITIAL_BALANCE - PRICE + (1e18 * 25 / 100)); // Original minus purchase + 0.25 DAI from distribution
  }

  function test_NewCycleAfterDistribution() public {
    // Make purchase in first cycle
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    // Complete first cycle
    vm.warp(block.timestamp + 30 days + 1);
    treasuryDistributor.distributeMonthlyRevenue();

    // Check new cycle started
    (uint256 cycle,,,) = treasuryDistributor.getCycleInfo();
    assertEq(cycle, 1);

    // Check buyers array is reset
    address[] memory buyers = treasuryDistributor.getCurrentBuyers();
    assertEq(buyers.length, 0);

    // Check eligible balances are reset
    assertEq(treasuryDistributor.totalEligible(), 0);

    // Make purchase in new cycle
    vm.prank(buyer2);
    vendingMachine.vendFromTrack(1, address(usdc), buyer2);

    // Buyer2 should have 2 VVT total but only 1 VVT eligible (new purchase)
    assertEq(voteToken.balanceOf(buyer2), PRICE);
    assertEq(treasuryDistributor.getBuyerEligibleBalance(buyer2), PRICE);
  }

  function test_NoPurchasesInCycle() public {
    // Fast forward to end of cycle without purchases
    vm.warp(block.timestamp + 30 days + 1);

    // Should complete without error
    treasuryDistributor.distributeMonthlyRevenue();

    // Check new cycle started
    (uint256 cycle,,,) = treasuryDistributor.getCycleInfo();
    assertEq(cycle, 1);
  }

  function test_OnlyTreasuryRoleCanWithdraw() public {
    // Make purchase to generate revenue
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    // Try to withdraw as non-treasury
    vm.prank(buyer2);
    vm.expectRevert();
    vendingMachine.withdrawRevenue(buyer2);

    // Treasury distributor should be able to withdraw
    vm.warp(block.timestamp + 30 days + 1);
    treasuryDistributor.distributeMonthlyRevenue();

    // Verify revenue was withdrawn
    assertEq(usdc.balanceOf(address(vendingMachine)), 0);
  }

  function test_EOATreasuryCompatibility() public {
    // Set an EOA as treasury instead of the distributor contract
    address eoaTreasury = address(0x9999);
    vendingMachine.setTreasuryDistributor(eoaTreasury);

    // Make a purchase - should not revert even though EOA can't handle onPurchase
    vm.prank(buyer1);
    uint256 returnedPrice = vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    // Verify purchase succeeded
    assertEq(returnedPrice, PRICE);
    assertEq(voteToken.balanceOf(buyer1), PRICE);

    // EOA treasury should be able to withdraw revenue directly
    vm.prank(eoaTreasury);
    vendingMachine.withdrawRevenue(eoaTreasury);

    // Verify withdrawal succeeded
    assertEq(usdc.balanceOf(eoaTreasury), PRICE);
    assertEq(usdc.balanceOf(address(vendingMachine)), 0);
  }

  function test_PreventDoubleDistribution() public {
    // Make purchases
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1);

    // Complete cycle
    vm.warp(block.timestamp + 30 days + 1);
    treasuryDistributor.distributeMonthlyRevenue();

    // Try to distribute again without new cycle
    vm.expectRevert();
    treasuryDistributor.distributeMonthlyRevenue();
  }

  function test_CalculateBuyerRevShare() public {
    // Make purchases from multiple buyers
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdc), buyer1); // $100 USDC

    vm.prank(buyer2);
    vendingMachine.vendFromTrack(0, address(usdt), buyer2); // $100 USDT

    vm.prank(buyer3);
    vendingMachine.vendFromTrack(0, address(dai), buyer3); // $100 DAI

    // Make an additional purchase from buyer1
    vm.prank(buyer1);
    vendingMachine.vendFromTrack(0, address(usdt), buyer1); // Another $100 USDT

    // Calculate revenue share for buyer1 (should be 200/400 = 50% of total)
    (address[] memory tokens, uint256[] memory amounts) = treasuryDistributor.calculateBuyerRevShare(buyer1);

    // Verify token addresses
    assertEq(tokens.length, 3);
    assertEq(tokens[0], address(usdc));
    assertEq(tokens[1], address(usdt));
    assertEq(tokens[2], address(dai));

    // Buyer1 should get 50% of all accumulated revenue
    // USDC: 1e18 total, buyer1 gets 50% = 5e17
    assertEq(amounts[0], 5e17);
    // USDT: 2e18 total, buyer1 gets 50% = 1e18
    assertEq(amounts[1], 1e18);
    // DAI: 1e18 total, buyer1 gets 50% = 5e17
    assertEq(amounts[2], 5e17);

    // Calculate for buyer2 (should be 100/400 = 25% of total)
    (, amounts) = treasuryDistributor.calculateBuyerRevShare(buyer2);
    assertEq(amounts[0], 25e16); // USDC: 25% of 1e18
    assertEq(amounts[1], 5e17); // USDT: 25% of 2e18
    assertEq(amounts[2], 25e16); // DAI: 25% of 1e18

    // Calculate for buyer3 (should be 100/400 = 25% of total)
    (, amounts) = treasuryDistributor.calculateBuyerRevShare(buyer3);
    assertEq(amounts[0], 25e16); // USDC: 25% of 1e18
    assertEq(amounts[1], 5e17); // USDT: 25% of 2e18
    assertEq(amounts[2], 25e16); // DAI: 25% of 1e18

    // Calculate for non-buyer (should be all zeros)
    (, amounts) = treasuryDistributor.calculateBuyerRevShare(address(0xDEAD));
    assertEq(amounts[0], 0);
    assertEq(amounts[1], 0);
    assertEq(amounts[2], 0);
  }
}
