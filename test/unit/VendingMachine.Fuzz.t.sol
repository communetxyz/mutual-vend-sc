// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../../src/contracts/VendingMachine.sol';
import {VoteToken} from '../../src/contracts/VoteToken.sol';
import {IVendingMachine} from '../../src/interfaces/IVendingMachine.sol';

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Test, console2} from 'forge-std/Test.sol';

contract MockERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

contract VendingMachineFuzzTest is Test {
  VendingMachine public vendingMachine;
  VoteToken public voteToken;
  MockERC20 public usdc;
  MockERC20 public usdt;
  MockERC20 public dai;

  address public owner = address(0x1);
  address public operator = address(0x2);
  address public treasury = address(0x3);
  address public user = address(0x4);

  uint8 constant NUM_TRACKS = 10;
  uint256 constant MAX_STOCK = 100;

  function setUp() public {
    vm.startPrank(owner);

    // Deploy mock tokens
    usdc = new MockERC20('USD Coin', 'USDC');
    usdt = new MockERC20('Tether', 'USDT');
    dai = new MockERC20('DAI', 'DAI');

    // Create initial accepted tokens array
    address[] memory acceptedTokens = new address[](3);
    acceptedTokens[0] = address(usdc);
    acceptedTokens[1] = address(usdt);
    acceptedTokens[2] = address(dai);

    // Deploy vending machine
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](0);
    uint256[] memory initialStocks = new uint256[](0);
    uint256[] memory initialPrices = new uint256[](0);

    vendingMachine = new VendingMachine(
      NUM_TRACKS, MAX_STOCK, 'VendingVotes', 'VVOTE', acceptedTokens, initialProducts, initialStocks, initialPrices
    );

    voteToken = vendingMachine.voteToken();

    // Setup roles
    vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), operator);
    vendingMachine.grantRole(vendingMachine.TREASURY_ROLE(), treasury);

    vm.stopPrank();
  }

  // Fuzz test for constructor parameters
  function testFuzz_Constructor(
    uint8 _numTracks,
    uint256 _maxStock,
    string memory _tokenName,
    string memory _tokenSymbol
  ) public {
    vm.assume(_numTracks > 0);
    vm.assume(_maxStock > 0);
    vm.assume(bytes(_tokenName).length > 0);
    vm.assume(bytes(_tokenSymbol).length > 0);

    address[] memory tokens = new address[](1);
    tokens[0] = address(usdc);

    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](0);
    uint256[] memory initialStocks = new uint256[](0);
    uint256[] memory initialPrices = new uint256[](0);

    VendingMachine vm = new VendingMachine(
      _numTracks, _maxStock, _tokenName, _tokenSymbol, tokens, initialProducts, initialStocks, initialPrices
    );

    assertEq(vm.NUM_TRACKS(), _numTracks);
    assertEq(vm.MAX_STOCK_PER_TRACK(), _maxStock);
    assertTrue(vm.isTokenAccepted(address(usdc)));
  }

  // Fuzz test for loadTrack function
  function testFuzz_LoadTrack(uint8 trackId, string memory productName, string memory imageURI, uint256 stock) public {
    vm.assume(trackId < NUM_TRACKS);
    vm.assume(stock <= MAX_STOCK);

    IVendingMachine.Product memory product = IVendingMachine.Product({name: productName, imageURI: imageURI});

    vm.prank(operator);
    vendingMachine.loadTrack(trackId, product, stock);

    IVendingMachine.Track memory track = vendingMachine.getTrack(trackId);
    assertEq(track.product.name, productName);
    assertEq(track.product.imageURI, imageURI);
    assertEq(track.stock, stock);
  }

  // Fuzz test for loadMultipleTracks
  function testFuzz_LoadMultipleTracks(uint8[] memory trackIds, string[] memory names, uint256[] memory stocks) public {
    // Bound array lengths and return early if invalid
    if (trackIds.length == 0 || trackIds.length > 3) return;
    if (trackIds.length != names.length || trackIds.length != stocks.length) return;

    // Validate and bound track IDs and stocks
    for (uint256 i = 0; i < trackIds.length; i++) {
      trackIds[i] = trackIds[i] % NUM_TRACKS;
      stocks[i] = stocks[i] % (MAX_STOCK + 1);
    }

    // Create products array
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](trackIds.length);
    for (uint256 i = 0; i < trackIds.length; i++) {
      products[i] = IVendingMachine.Product({name: names[i], imageURI: string(abi.encodePacked('uri_', i))});
    }

    vm.prank(operator);
    vendingMachine.loadMultipleTracks(trackIds, products, stocks);

    // Verify all tracks loaded correctly
    for (uint256 i = 0; i < trackIds.length; i++) {
      IVendingMachine.Track memory track = vendingMachine.getTrack(trackIds[i]);
      assertEq(track.product.name, names[i]);
      assertEq(track.stock, stocks[i]);
    }
  }

  // Fuzz test for setTrackPrice
  function testFuzz_SetTrackPrice(uint8 trackId, uint256 price) public {
    vm.assume(trackId < NUM_TRACKS);
    vm.assume(price > 0);
    vm.assume(price < type(uint256).max);

    vm.prank(operator);
    vendingMachine.setTrackPrice(trackId, price);

    IVendingMachine.Track memory track = vendingMachine.getTrack(trackId);
    assertEq(track.price, price);
  }

  // Fuzz test for restockTrack
  function testFuzz_RestockTrack(uint8 trackId, uint256 initialStock, uint256 additionalStock) public {
    trackId = trackId % NUM_TRACKS;
    initialStock = bound(initialStock, 1, MAX_STOCK / 2);
    additionalStock = bound(additionalStock, 1, MAX_STOCK / 2);

    // First load the track
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Test Product', imageURI: 'ipfs://test'});

    vm.startPrank(operator);
    vendingMachine.loadTrack(trackId, product, initialStock);
    vendingMachine.restockTrack(trackId, additionalStock);
    vm.stopPrank();

    assertEq(vendingMachine.getTrackInventory(trackId), initialStock + additionalStock);
  }

  // Fuzz test for vendFromTrack
  function testFuzz_VendFromTrack(uint8 trackId, uint256 price, address recipient, uint256 userBalance) public {
    vm.assume(trackId < NUM_TRACKS);
    vm.assume(price > 0 && price < 1e30); // Reasonable price range
    vm.assume(recipient != address(0));
    vm.assume(userBalance >= price);

    // Setup track with product
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Fuzz Product', imageURI: 'ipfs://fuzz'});

    vm.startPrank(operator);
    vendingMachine.loadTrack(trackId, product, 10);
    vendingMachine.setTrackPrice(trackId, price);
    vm.stopPrank();

    // Mint tokens to user and approve
    usdc.mint(user, userBalance);
    vm.startPrank(user);
    usdc.approve(address(vendingMachine), price);

    uint256 initialStock = vendingMachine.getTrackInventory(trackId);
    uint256 initialVoteBalance = voteToken.balanceOf(recipient);

    vendingMachine.vendFromTrack(trackId, address(usdc), recipient);

    // Verify state changes
    assertEq(vendingMachine.getTrackInventory(trackId), initialStock - 1);
    assertEq(voteToken.balanceOf(recipient), initialVoteBalance + price);
    assertEq(usdc.balanceOf(address(vendingMachine)), price);

    vm.stopPrank();
  }

  // Fuzz test for vendFromTrack with zero recipient (burn)
  function testFuzz_VendWithZeroRecipient(uint8 trackId, uint256 price) public {
    vm.assume(trackId < NUM_TRACKS);
    vm.assume(price > 0 && price < 1e30);

    // Setup track
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Burn Product', imageURI: 'ipfs://burn'});

    vm.startPrank(operator);
    vendingMachine.loadTrack(trackId, product, 5);
    vendingMachine.setTrackPrice(trackId, price);
    vm.stopPrank();

    // Mint and approve
    usdc.mint(user, price);
    vm.startPrank(user);
    usdc.approve(address(vendingMachine), price);

    uint256 totalSupplyBefore = voteToken.totalSupply();

    // Vend with zero recipient
    vendingMachine.vendFromTrack(trackId, address(usdc), address(0));

    // Verify no vote tokens were minted
    assertEq(voteToken.totalSupply(), totalSupplyBefore);

    vm.stopPrank();
  }

  // Fuzz test for configurePaymentTokens
  function testFuzz_ConfigurePaymentTokens(address[] memory tokens) public {
    // Bound array length and return early if invalid
    if (tokens.length == 0 || tokens.length > 5) return;

    // Clean up tokens array - remove zeros and duplicates
    address[] memory cleanTokens = new address[](tokens.length);
    uint256 cleanCount = 0;

    for (uint256 i = 0; i < tokens.length; i++) {
      if (tokens[i] == address(0)) continue;

      // Check for duplicates
      bool isDuplicate = false;
      for (uint256 j = 0; j < cleanCount; j++) {
        if (cleanTokens[j] == tokens[i]) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        cleanTokens[cleanCount] = tokens[i];
        cleanCount++;
      }
    }

    if (cleanCount == 0) return;

    // Create a new array of the correct size and copy elements
    address[] memory finalTokens = new address[](cleanCount);
    for (uint256 i = 0; i < cleanCount; i++) {
      finalTokens[i] = cleanTokens[i];
    }

    vm.prank(operator);
    vendingMachine.configurePaymentTokens(finalTokens);

    // Verify all tokens are accepted
    for (uint256 i = 0; i < cleanCount; i++) {
      assertTrue(vendingMachine.isTokenAccepted(finalTokens[i]));
    }

    // Verify old tokens are not accepted
    assertFalse(vendingMachine.isTokenAccepted(address(0x999)));
  }

  // Fuzz test for withdrawRevenue
  function testFuzz_WithdrawRevenue(address token, address to, uint256 amount, uint256 contractBalance) public {
    vm.assume(token != address(0));
    vm.assume(to != address(0));
    vm.assume(amount > 0);
    vm.assume(contractBalance >= amount);
    vm.assume(contractBalance < type(uint128).max);

    // Create a new token and mint to vending machine
    MockERC20 testToken = new MockERC20('Test', 'TST');
    testToken.mint(address(vendingMachine), contractBalance);

    uint256 initialBalance = testToken.balanceOf(to);

    address[] memory withdrawTokens = new address[](1);
    withdrawTokens[0] = address(testToken);
    uint256[] memory withdrawAmounts = new uint256[](1);
    withdrawAmounts[0] = amount;

    vm.prank(treasury);
    vendingMachine.withdrawRevenue(withdrawTokens, to, withdrawAmounts);

    assertEq(testToken.balanceOf(to), initialBalance + amount);
    assertEq(testToken.balanceOf(address(vendingMachine)), contractBalance - amount);
  }

  // Fuzz test for edge cases in stock management
  function testFuzz_StockBoundaries(uint8 trackId, uint256 stock) public {
    vm.assume(trackId < NUM_TRACKS);

    // Test at MAX_STOCK boundary
    if (stock > MAX_STOCK) {
      IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Boundary Test', imageURI: ''});

      vm.prank(operator);
      vm.expectRevert(IVendingMachine.InvalidStock.selector);
      vendingMachine.loadTrack(trackId, product, stock);
    } else if (stock == 0) {
      // Test with zero stock (should be allowed for clearing)
      IVendingMachine.Product memory product = IVendingMachine.Product({name: '', imageURI: ''});

      vm.prank(operator);
      vendingMachine.loadTrack(trackId, product, 0);

      assertEq(vendingMachine.getTrackInventory(trackId), 0);
    }
  }

  // Invariant test: Total stock should never exceed MAX_STOCK per track
  function testFuzz_InvariantMaxStock(uint8 trackId, uint256[] memory restockAmounts) public {
    trackId = trackId % NUM_TRACKS;
    if (restockAmounts.length == 0 || restockAmounts.length > 5) return;

    // Load initial track
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Invariant Test', imageURI: 'test'});

    vm.startPrank(operator);
    vendingMachine.loadTrack(trackId, product, 1);

    uint256 currentStock = 1;

    for (uint256 i = 0; i < restockAmounts.length; i++) {
      // Bound restock amount to reasonable range
      uint256 restockAmount = bound(restockAmounts[i], 0, MAX_STOCK * 2);

      if (restockAmount == 0) continue;

      // Check if adding would exceed MAX_STOCK
      bool wouldExceed = currentStock + restockAmount > MAX_STOCK;

      if (wouldExceed) {
        vm.expectRevert(IVendingMachine.InvalidStock.selector);
        vendingMachine.restockTrack(trackId, restockAmount);
      } else {
        vendingMachine.restockTrack(trackId, restockAmount);
        currentStock = currentStock + restockAmount;
        assertEq(vendingMachine.getTrackInventory(trackId), currentStock);
      }
    }

    vm.stopPrank();
  }

  // Fuzz test for product overwrite functionality
  function testFuzz_ProductOverwrite(
    uint8 trackId,
    string memory name1,
    string memory name2,
    uint256 stock1,
    uint256 stock2
  ) public {
    trackId = trackId % NUM_TRACKS;
    stock1 = bound(stock1, 1, MAX_STOCK);
    stock2 = bound(stock2, 1, MAX_STOCK);

    // Ensure names are valid
    if (bytes(name1).length == 0 || bytes(name1).length >= 100) name1 = 'Product1';
    if (bytes(name2).length == 0 || bytes(name2).length >= 100) name2 = 'Product2';

    IVendingMachine.Product memory product1 = IVendingMachine.Product({name: name1, imageURI: 'uri1'});

    IVendingMachine.Product memory product2 = IVendingMachine.Product({name: name2, imageURI: 'uri2'});

    vm.startPrank(operator);

    // Load first product
    vendingMachine.loadTrack(trackId, product1, stock1);
    IVendingMachine.Track memory track1 = vendingMachine.getTrack(trackId);
    assertEq(track1.product.name, name1);
    assertEq(track1.stock, stock1);

    // Overwrite with second product
    vendingMachine.loadTrack(trackId, product2, stock2);
    IVendingMachine.Track memory track2 = vendingMachine.getTrack(trackId);
    assertEq(track2.product.name, name2);
    assertEq(track2.stock, stock2);

    vm.stopPrank();
  }
}
