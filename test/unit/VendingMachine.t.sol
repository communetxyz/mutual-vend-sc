// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from 'forge-std/Test.sol';
import {VendingMachine} from 'contracts/VendingMachine.sol';
import {VoteToken} from 'contracts/VoteToken.sol';
import {IVendingMachine} from 'interfaces/IVendingMachine.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract VendingMachineTest is Test {
  VendingMachine public machine;
  VoteToken public voteToken;
  MockERC20 public stablecoin;
  MockERC20 public stablecoin2;

  address public admin = makeAddr('admin');
  address public operator = makeAddr('operator');
  address public treasury = makeAddr('treasury');
  address public buyer = makeAddr('buyer');

  uint8 constant NUM_TRACKS = 3;
  uint256 constant MAX_STOCK = 10;
  uint256 constant PRICE = 2e18;

  function setUp() public {
    stablecoin = new MockERC20('Mock USDC', 'mUSDC');
    stablecoin2 = new MockERC20('Mock DAI', 'mDAI');

    address[] memory tokens = new address[](1);
    tokens[0] = address(stablecoin);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](2);
    products[0] = IVendingMachine.Product('Cola', 'ipfs://cola');
    products[1] = IVendingMachine.Product('Water', 'ipfs://water');

    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 5;
    stocks[1] = 8;

    uint256[] memory prices = new uint256[](2);
    prices[0] = PRICE;
    prices[1] = 1e18;

    vm.prank(admin);
    machine = new VendingMachine(NUM_TRACKS, MAX_STOCK, 'VoteToken', 'VT', tokens, products, stocks, prices);

    voteToken = machine.voteToken();

    // Grant roles
    vm.startPrank(admin);
    machine.grantRole(machine.OPERATOR_ROLE(), operator);
    machine.grantRole(machine.TREASURY_ROLE(), treasury);
    vm.stopPrank();

    // Fund buyer
    stablecoin.mint(buyer, 100e18);
    stablecoin2.mint(buyer, 100e18);
  }

  // === Constructor ===

  function test_constructor_setsTracksCorrectly() public view {
    assertEq(machine.NUM_TRACKS(), NUM_TRACKS);
    assertEq(machine.MAX_STOCK_PER_TRACK(), MAX_STOCK);

    IVendingMachine.Track memory t0 = machine.getTrack(0);
    assertEq(t0.product.name, 'Cola');
    assertEq(t0.stock, 5);
    assertEq(t0.price, PRICE);

    IVendingMachine.Track memory t1 = machine.getTrack(1);
    assertEq(t1.product.name, 'Water');
    assertEq(t1.stock, 8);
    assertEq(t1.price, 1e18);

    // Track 2 should be empty
    IVendingMachine.Track memory t2 = machine.getTrack(2);
    assertEq(t2.stock, 0);
  }

  function test_constructor_deploysVoteToken() public view {
    assertEq(voteToken.name(), 'VoteToken');
    assertEq(voteToken.symbol(), 'VT');
    assertTrue(voteToken.hasRole(voteToken.MINTER_ROLE(), address(machine)));
  }

  function test_constructor_setsAcceptedTokens() public view {
    assertTrue(machine.isTokenAccepted(address(stablecoin)));
    assertFalse(machine.isTokenAccepted(address(stablecoin2)));
  }

  function test_constructor_revertsZeroTracks() public {
    address[] memory tokens = new address[](0);
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](0);
    uint256[] memory stocks = new uint256[](0);
    uint256[] memory prices = new uint256[](0);

    vm.expectRevert(IVendingMachine.InvalidTrackCount.selector);
    new VendingMachine(0, 10, 'T', 'T', tokens, products, stocks, prices);
  }

  function test_constructor_revertsZeroMaxStock() public {
    address[] memory tokens = new address[](0);
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](0);
    uint256[] memory stocks = new uint256[](0);
    uint256[] memory prices = new uint256[](0);

    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    new VendingMachine(3, 0, 'T', 'T', tokens, products, stocks, prices);
  }

  // === Track Management ===

  function test_loadTrack() public {
    vm.prank(operator);
    machine.loadTrack(2, IVendingMachine.Product('Juice', 'ipfs://juice'), 7);

    IVendingMachine.Track memory t = machine.getTrack(2);
    assertEq(t.product.name, 'Juice');
    assertEq(t.stock, 7);
  }

  function test_loadTrack_revertsNonOperator() public {
    vm.prank(buyer);
    vm.expectRevert();
    machine.loadTrack(0, IVendingMachine.Product('X', 'x'), 1);
  }

  function test_loadTrack_revertsInvalidTrackId() public {
    vm.prank(operator);
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    machine.loadTrack(NUM_TRACKS, IVendingMachine.Product('X', 'x'), 1);
  }

  function test_loadTrack_revertsExceedsMaxStock() public {
    vm.prank(operator);
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    machine.loadTrack(0, IVendingMachine.Product('X', 'x'), MAX_STOCK + 1);
  }

  function test_loadMultipleTracks() public {
    uint8[] memory ids = new uint8[](2);
    ids[0] = 0;
    ids[1] = 2;
    IVendingMachine.Product[] memory prods = new IVendingMachine.Product[](2);
    prods[0] = IVendingMachine.Product('A', 'a');
    prods[1] = IVendingMachine.Product('B', 'b');
    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 3;
    stocks[1] = 4;

    vm.prank(operator);
    machine.loadMultipleTracks(ids, prods, stocks);

    assertEq(machine.getTrack(0).product.name, 'A');
    assertEq(machine.getTrack(2).product.name, 'B');
  }

  function test_restockTrack() public {
    uint256 before = machine.getTrackInventory(0);
    vm.prank(operator);
    machine.restockTrack(0, 3);
    assertEq(machine.getTrackInventory(0), before + 3);
  }

  function test_restockTrack_revertsExceedsMax() public {
    vm.prank(operator);
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    machine.restockTrack(0, MAX_STOCK); // 5 + 10 > 10
  }

  function test_restockTrack_revertsZero() public {
    vm.prank(operator);
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    machine.restockTrack(0, 0);
  }

  function test_setTrackPrice() public {
    vm.prank(operator);
    machine.setTrackPrice(0, 5e18);
    assertEq(machine.getTrack(0).price, 5e18);
  }

  function test_setTrackPrice_revertsZero() public {
    vm.prank(operator);
    vm.expectRevert(IVendingMachine.InvalidPrice.selector);
    machine.setTrackPrice(0, 0);
  }

  // === Payment Token Configuration ===

  function test_configurePaymentTokens() public {
    address[] memory newTokens = new address[](2);
    newTokens[0] = address(stablecoin);
    newTokens[1] = address(stablecoin2);

    vm.prank(operator);
    machine.configurePaymentTokens(newTokens);

    assertTrue(machine.isTokenAccepted(address(stablecoin)));
    assertTrue(machine.isTokenAccepted(address(stablecoin2)));
  }

  function test_configurePaymentTokens_removesOldTokens() public {
    address[] memory newTokens = new address[](1);
    newTokens[0] = address(stablecoin2);

    vm.prank(operator);
    machine.configurePaymentTokens(newTokens);

    assertFalse(machine.isTokenAccepted(address(stablecoin)));
    assertTrue(machine.isTokenAccepted(address(stablecoin2)));
  }

  // === Vending (Purchase) ===

  function test_vendFromTrack() public {
    vm.startPrank(buyer);
    stablecoin.approve(address(machine), PRICE);
    uint256 paid = machine.vendFromTrack(0, address(stablecoin), buyer);
    vm.stopPrank();

    assertEq(paid, PRICE);
    assertEq(machine.getTrackInventory(0), 4); // was 5
    assertEq(voteToken.balanceOf(buyer), PRICE); // minted vote tokens
    assertEq(stablecoin.balanceOf(address(machine)), PRICE);
  }

  function test_vendFromTrack_noVoteTokenIfZeroRecipient() public {
    vm.startPrank(buyer);
    stablecoin.approve(address(machine), PRICE);
    machine.vendFromTrack(0, address(stablecoin), address(0));
    vm.stopPrank();

    assertEq(voteToken.totalSupply(), 0);
  }

  function test_vendFromTrack_revertsTokenNotAccepted() public {
    vm.startPrank(buyer);
    stablecoin2.approve(address(machine), PRICE);
    vm.expectRevert(IVendingMachine.TokenNotAccepted.selector);
    machine.vendFromTrack(0, address(stablecoin2), buyer);
    vm.stopPrank();
  }

  function test_vendFromTrack_revertsInsufficientStock() public {
    // Drain all stock
    vm.startPrank(buyer);
    stablecoin.approve(address(machine), PRICE * 10);
    for (uint256 i = 0; i < 5; i++) {
      machine.vendFromTrack(0, address(stablecoin), buyer);
    }
    vm.expectRevert(IVendingMachine.InsufficientStock.selector);
    machine.vendFromTrack(0, address(stablecoin), buyer);
    vm.stopPrank();
  }

  function test_vendFromTrack_revertsPriceNotSet() public {
    // Track 2 has no price set
    vm.prank(operator);
    machine.loadTrack(2, IVendingMachine.Product('Snack', 'ipfs://snack'), 5);

    vm.startPrank(buyer);
    stablecoin.approve(address(machine), 1e18);
    vm.expectRevert(IVendingMachine.PriceNotSet.selector);
    machine.vendFromTrack(2, address(stablecoin), buyer);
    vm.stopPrank();
  }

  // === Revenue Withdrawal ===

  function test_withdrawRevenue() public {
    // Make a purchase first
    vm.startPrank(buyer);
    stablecoin.approve(address(machine), PRICE);
    machine.vendFromTrack(0, address(stablecoin), buyer);
    vm.stopPrank();

    address[] memory tokens = new address[](1);
    tokens[0] = address(stablecoin);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = PRICE;

    vm.prank(treasury);
    machine.withdrawRevenue(tokens, treasury, amounts);

    assertEq(stablecoin.balanceOf(treasury), PRICE);
    assertEq(stablecoin.balanceOf(address(machine)), 0);
  }

  function test_withdrawRevenue_revertsNonTreasury() public {
    address[] memory tokens = new address[](1);
    tokens[0] = address(stablecoin);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1;

    vm.prank(buyer);
    vm.expectRevert();
    machine.withdrawRevenue(tokens, buyer, amounts);
  }

  function test_withdrawRevenue_revertsInsufficientBalance() public {
    address[] memory tokens = new address[](1);
    tokens[0] = address(stablecoin);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 999e18;

    vm.prank(treasury);
    vm.expectRevert(IVendingMachine.InsufficientBalance.selector);
    machine.withdrawRevenue(tokens, treasury, amounts);
  }

  // === View Functions ===

  function test_getAllTracks() public view {
    IVendingMachine.Track[] memory all = machine.getAllTracks();
    assertEq(all.length, NUM_TRACKS);
    assertEq(all[0].product.name, 'Cola');
    assertEq(all[1].product.name, 'Water');
  }

  function test_getAcceptedTokens() public view {
    address[] memory tokens = machine.getAcceptedTokens();
    assertEq(tokens.length, 1);
    assertEq(tokens[0], address(stablecoin));
  }
}
