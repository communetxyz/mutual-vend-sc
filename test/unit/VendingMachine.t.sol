// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest, MockStablecoin} from '../BaseTest.sol';
import {VendingMachine} from '../../src/contracts/VendingMachine.sol';
import {VoteToken} from '../../src/contracts/VoteToken.sol';
import {IVendingMachine} from '../../src/interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

contract VendingMachineTest is BaseTest {
  // Events
  event TrackLoaded(uint8 indexed trackId, string itemName, string imageURI, uint256 quantity);
  event TrackRestocked(uint8 indexed trackId, uint256 additionalStock);
  event TrackPriceSet(uint8 indexed trackId, uint256 dollarPrice);
  event TokenAcceptanceUpdated(address indexed token, bool accepted);
  event ItemVended(uint8 indexed trackId, address indexed customer, address token, uint256 quantity, uint256 amount);
  event RevenueWithdrawn(address indexed token, address indexed to, uint256 amount);

  // Constructor tests
  function test_ConstructorWhenNumTracksIsZero() external {
    vm.startPrank(owner);
    
    DeploymentConfig memory config = getDeploymentConfig();
    config.numTracks = 0;
    
    // Prepare empty deployment parameters
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](0);
    uint256[] memory initialStocks = new uint256[](0);
    uint256[] memory initialPrices = new uint256[](0);

    // it reverts with InvalidTrackCount
    vm.expectRevert(IVendingMachine.InvalidTrackCount.selector);
    new VendingMachine(
      config.numTracks, 
      config.maxStockPerTrack, 
      config.tokenName, 
      config.tokenSymbol, 
      config.acceptedTokens, 
      initialProducts, 
      initialStocks, 
      initialPrices
    );
    
    vm.stopPrank();
  }

  function test_ConstructorWhenMaxStockPerTrackIsZero() external {
    vm.startPrank(owner);
    
    DeploymentConfig memory config = getDeploymentConfig();
    config.maxStockPerTrack = 0;
    
    // Prepare empty deployment parameters
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](0);
    uint256[] memory initialStocks = new uint256[](0);
    uint256[] memory initialPrices = new uint256[](0);

    // it reverts with InvalidStock
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    new VendingMachine(
      config.numTracks,
      config.maxStockPerTrack,
      config.tokenName,
      config.tokenSymbol,
      config.acceptedTokens,
      initialProducts,
      initialStocks,
      initialPrices
    );
    
    vm.stopPrank();
  }

  function test_ConstructorWhenInitialProductsArrayLengthExceedsNumTracks() external {
    vm.startPrank(owner);
    
    DeploymentConfig memory config = getDeploymentConfig();
    
    // Create products exceeding num tracks
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](config.numTracks + 1);
    for (uint8 i = 0; i <= config.numTracks; i++) {
      initialProducts[i] = IVendingMachine.Product({
        name: string(abi.encodePacked('Product', i)), 
        imageURI: 'ipfs://product'
      });
    }
    uint256[] memory initialStocks = new uint256[](config.numTracks + 1);
    for (uint8 i = 0; i <= config.numTracks; i++) {
      initialStocks[i] = 10;
    }
    uint256[] memory initialPrices = new uint256[](config.numTracks + 1);
    for (uint8 i = 0; i <= config.numTracks; i++) {
      initialPrices[i] = 1e18;
    }

    // Constructor only processes up to NUM_TRACKS, ignores extra elements
    VendingMachine newVendingMachine = new VendingMachine(
      config.numTracks,
      config.maxStockPerTrack,
      config.tokenName,
      config.tokenSymbol,
      config.acceptedTokens,
      initialProducts,
      initialStocks,
      initialPrices
    );
    
    // Only NUM_TRACKS tracks should be initialized
    for (uint8 i = 0; i < config.numTracks; i++) {
      IVendingMachine.Track memory track = newVendingMachine.getTrack(i);
      assertEq(track.product.name, string(abi.encodePacked('Product', i)));
      assertEq(track.stock, 10);
      assertEq(track.price, 1e18);
    }
    
    vm.stopPrank();
  }

  function test_ConstructorWhenArraysHaveMismatchedLengths() external {
    vm.startPrank(owner);
    
    DeploymentConfig memory config = getDeploymentConfig();
    
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](2);
    initialProducts[0] = IVendingMachine.Product({name: 'Product1', imageURI: 'ipfs://1'});
    initialProducts[1] = IVendingMachine.Product({name: 'Product2', imageURI: 'ipfs://2'});
    uint256[] memory initialStocks = new uint256[](1);
    initialStocks[0] = 10;
    uint256[] memory initialPrices = new uint256[](2);
    initialPrices[0] = 1e18;
    initialPrices[1] = 2e18;

    // Constructor doesn't validate array length matching, it uses what's available
    VendingMachine newVendingMachine = new VendingMachine(
      config.numTracks,
      config.maxStockPerTrack,
      config.tokenName,
      config.tokenSymbol,
      config.acceptedTokens,
      initialProducts,
      initialStocks,
      initialPrices
    );
    
    // Track 0 should have product, stock, and price
    IVendingMachine.Track memory track0 = newVendingMachine.getTrack(0);
    assertEq(track0.product.name, 'Product1');
    assertEq(track0.stock, 10);
    assertEq(track0.price, 1e18);
    
    // Track 1 should have product and price but no stock (default 0)
    IVendingMachine.Track memory track1 = newVendingMachine.getTrack(1);
    assertEq(track1.product.name, 'Product2');
    assertEq(track1.stock, 0);
    assertEq(track1.price, 2e18);
    
    vm.stopPrank();
  }

  function test_ConstructorWhenAllParametersAreValid() external {
    // Create custom config with initial products
    DeploymentConfig memory config;
    config.numTracks = DEFAULT_NUM_TRACKS;
    config.maxStockPerTrack = DEFAULT_MAX_STOCK;
    config.tokenName = 'Test Token';
    config.tokenSymbol = 'TT';
    config.acceptedTokens = new address[](2);
    config.acceptedTokens[0] = address(usdc);
    config.acceptedTokens[1] = address(usdt);
    
    // Add initial products
    config.products = new ProductConfig[](2);
    config.products[0] = ProductConfig({
      name: 'Product1',
      ipfsHash: 'ipfs://1',
      stock: 10,
      price: 1e18
    });
    config.products[1] = ProductConfig({
      name: 'Product2',
      ipfsHash: 'ipfs://2',
      stock: 20,
      price: 2e18
    });

    // Prepare deployment parameters
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](config.products.length);
    uint256[] memory initialStocks = new uint256[](config.products.length);
    uint256[] memory initialPrices = new uint256[](config.products.length);

    for (uint256 i = 0; i < config.products.length; i++) {
      initialProducts[i] = IVendingMachine.Product(config.products[i].name, config.products[i].ipfsHash);
      initialStocks[i] = config.products[i].stock;
      initialPrices[i] = config.products[i].price;
    }

    vm.prank(owner);
    VendingMachine newVendingMachine = new VendingMachine(
      config.numTracks,
      config.maxStockPerTrack,
      config.tokenName,
      config.tokenSymbol,
      config.acceptedTokens,
      initialProducts,
      initialStocks,
      initialPrices
    );

    VoteToken newVoteToken = newVendingMachine.voteToken();

    // it sets NUM_TRACKS correctly
    assertEq(newVendingMachine.NUM_TRACKS(), config.numTracks);
    
    // it sets MAX_STOCK_PER_TRACK correctly
    assertEq(newVendingMachine.MAX_STOCK_PER_TRACK(), config.maxStockPerTrack);
    
    // it deploys and sets the vote token
    assertNotEq(address(newVoteToken), address(0));
    
    // it grants MINTER_ROLE to the contract
    assertTrue(newVoteToken.hasRole(newVoteToken.MINTER_ROLE(), address(newVendingMachine)));
    
    // it initializes tracks with provided products
    IVendingMachine.Track memory track0 = newVendingMachine.getTrack(0);
    assertEq(track0.product.name, 'Product1');
    assertEq(track0.stock, 10);
    assertEq(track0.price, 1e18);
    
    // it sets initial accepted tokens
    assertTrue(newVendingMachine.isTokenAccepted(address(usdc)));
    assertTrue(newVendingMachine.isTokenAccepted(address(usdt)));
    
    // it grants DEFAULT_ADMIN_ROLE to deployer
    assertTrue(newVendingMachine.hasRole(newVendingMachine.DEFAULT_ADMIN_ROLE(), owner));
  }

  // LoadTrack tests
  function test_LoadTrackWhenCallerDoesNotHaveOPERATOR_ROLE() external {
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});

    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, vendingMachine.OPERATOR_ROLE())
    );
    vm.prank(nonOperator);
    vendingMachine.loadTrack(0, product, 10);
  }

  function test_LoadTrackWhenTrackIdIsInvalid() external {
    vm.prank(operator);
    
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});

    // it reverts with InvalidTrackId
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    vendingMachine.loadTrack(DEFAULT_NUM_TRACKS, product, 10);
  }

  function test_LoadTrackWhenStockExceedsMAX_STOCK_PER_TRACK() external {
    vm.prank(operator);
    
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});

    // it reverts with InvalidStock
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    vendingMachine.loadTrack(0, product, DEFAULT_MAX_STOCK + 1);
  }

  modifier whenCalledByOperator() {
    vm.startPrank(operator);
    _;
    vm.stopPrank();
  }

  function test_LoadTrackWhenParametersAreValid() external whenCalledByOperator {
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    
    // it emits TrackLoaded event
    vm.expectEmit(true, false, false, true);
    emit TrackLoaded(0, 'Soda', 'ipfs://soda', 10);
    
    vendingMachine.loadTrack(0, product, 10);
    
    IVendingMachine.Track memory track = vendingMachine.getTrack(0);
    
    // it sets the product details
    assertEq(track.product.name, 'Soda');
    assertEq(track.product.imageURI, 'ipfs://soda');
    
    // it sets the stock
    assertEq(track.stock, 10);
    
    // it resets the price to zero
    assertEq(track.price, 0);
  }

  // LoadMultipleTracks tests
  function test_LoadMultipleTracksWhenCallerDoesNotHaveOPERATOR_ROLE() external {
    uint8[] memory trackIds = new uint8[](1);
    trackIds[0] = 0;
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](1);
    products[0] = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    uint256[] memory stocks = new uint256[](1);
    stocks[0] = 10;

    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, vendingMachine.OPERATOR_ROLE())
    );
    vm.prank(nonOperator);
    vendingMachine.loadMultipleTracks(trackIds, products, stocks);
  }

  function test_LoadMultipleTracksWhenArraysHaveMismatchedLengths() external whenCalledByOperator {
    uint8[] memory trackIds = new uint8[](2);
    trackIds[0] = 0;
    trackIds[1] = 1;
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](1);
    products[0] = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 10;
    stocks[1] = 20;

    // it reverts with ArrayLengthMismatch
    vm.expectRevert(IVendingMachine.ArrayLengthMismatch.selector);
    vendingMachine.loadMultipleTracks(trackIds, products, stocks);
  }

  function test_LoadMultipleTracksWhenAnyTrackIdIsInvalid() external whenCalledByOperator {
    uint8[] memory trackIds = new uint8[](2);
    trackIds[0] = 0;
    trackIds[1] = DEFAULT_NUM_TRACKS; // Invalid
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](2);
    products[0] = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    products[1] = IVendingMachine.Product({name: 'Chips', imageURI: 'ipfs://chips'});
    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 10;
    stocks[1] = 20;

    // it reverts with InvalidTrackId
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    vendingMachine.loadMultipleTracks(trackIds, products, stocks);
  }

  function test_LoadMultipleTracksWhenAnyStockExceedsMAX_STOCK_PER_TRACK() external whenCalledByOperator {
    uint8[] memory trackIds = new uint8[](2);
    trackIds[0] = 0;
    trackIds[1] = 1;
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](2);
    products[0] = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    products[1] = IVendingMachine.Product({name: 'Chips', imageURI: 'ipfs://chips'});
    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 10;
    stocks[1] = DEFAULT_MAX_STOCK + 1; // Exceeds max

    // it reverts with InvalidStock
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    vendingMachine.loadMultipleTracks(trackIds, products, stocks);
  }

  function test_LoadMultipleTracksWhenAllParametersAreValid() external whenCalledByOperator {
    uint8[] memory trackIds = new uint8[](2);
    trackIds[0] = 0;
    trackIds[1] = 1;
    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](2);
    products[0] = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    products[1] = IVendingMachine.Product({name: 'Chips', imageURI: 'ipfs://chips'});
    uint256[] memory stocks = new uint256[](2);
    stocks[0] = 20;
    stocks[1] = 30;

    // it emits TrackLoaded events for each track
    vm.expectEmit(true, false, false, true);
    emit TrackLoaded(0, 'Soda', 'ipfs://soda', stocks[0]);
    vm.expectEmit(true, false, false, true);
    emit TrackLoaded(1, 'Chips', 'ipfs://chips', stocks[1]);

    vendingMachine.loadMultipleTracks(trackIds, products, stocks);

    // it loads all specified tracks
    assertEq(vendingMachine.getTrack(0).product.name, 'Soda');
    assertEq(vendingMachine.getTrack(1).product.name, 'Chips');
    assertEq(vendingMachine.getTrack(0).stock, 20);
    assertEq(vendingMachine.getTrack(1).stock, 30);
  }

  // RestockTrack tests
  function test_RestockTrackWhenCallerDoesNotHaveOPERATOR_ROLE() external {
    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, vendingMachine.OPERATOR_ROLE())
    );
    vm.prank(nonOperator);
    vendingMachine.restockTrack(0, 10);
  }

  function test_RestockTrackWhenTrackIdIsInvalid() external whenCalledByOperator {
    // it reverts with InvalidTrackId
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    vendingMachine.restockTrack(DEFAULT_NUM_TRACKS, 10);
  }

  function test_RestockTrackWhenNewTotalStockExceedsMAX_STOCK_PER_TRACK() external whenCalledByOperator {
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);

    // it reverts with InvalidStock
    vm.expectRevert(IVendingMachine.InvalidStock.selector);
    vendingMachine.restockTrack(0, 20); // 40 + 20 = 60 > 50
  }

  function test_RestockTrackWhenParametersAreValid() external whenCalledByOperator {
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 10);

    // it emits TrackRestocked event
    vm.expectEmit(true, false, false, true);
    emit TrackRestocked(0, 20);

    vendingMachine.restockTrack(0, 20);

    // it increases the stock
    assertEq(vendingMachine.getTrackInventory(0), 30);
  }

  // SetTrackPrice tests
  function test_SetTrackPriceWhenCallerDoesNotHaveOPERATOR_ROLE() external {
    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, vendingMachine.OPERATOR_ROLE())
    );
    vm.prank(nonOperator);
    vendingMachine.setTrackPrice(0, 3e18);
  }

  function test_SetTrackPriceWhenTrackIdIsInvalid() external whenCalledByOperator {
    // it reverts with InvalidTrackId
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    vendingMachine.setTrackPrice(DEFAULT_NUM_TRACKS, 3e18);
  }

  function test_SetTrackPriceWhenParametersAreValid() external whenCalledByOperator {
    // it emits TrackPriceSet event
    vm.expectEmit(true, false, false, true);
    emit TrackPriceSet(0, 3e18);

    vendingMachine.setTrackPrice(0, 3e18);

    // it updates the price
    assertEq(vendingMachine.getTrack(0).price, 3e18);
  }

  // ConfigurePaymentTokens tests
  function test_ConfigurePaymentTokensWhenCallerDoesNotHaveOPERATOR_ROLE() external {
    address[] memory tokens = new address[](1);
    tokens[0] = makeAddr('newToken');

    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, vendingMachine.OPERATOR_ROLE())
    );
    vm.prank(nonOperator);
    vendingMachine.configurePaymentTokens(tokens);
  }

  function test_ConfigurePaymentTokensWhenCallerHasOPERATOR_ROLE() external whenCalledByOperator {
    address newToken = address(new MockStablecoin('New', 'NEW'));
    address[] memory tokens = new address[](1);
    tokens[0] = newToken;

    // it emits TokenAcceptanceUpdated events
    // Old tokens are removed
    vm.expectEmit(true, false, false, true);
    emit TokenAcceptanceUpdated(address(usdc), false);
    vm.expectEmit(true, false, false, true);
    emit TokenAcceptanceUpdated(address(usdt), false);
    vm.expectEmit(true, false, false, true);
    emit TokenAcceptanceUpdated(address(dai), false);
    // New token is added
    vm.expectEmit(true, false, false, true);
    emit TokenAcceptanceUpdated(newToken, true);

    vendingMachine.configurePaymentTokens(tokens);

    // it removes old accepted tokens
    assertFalse(vendingMachine.isTokenAccepted(address(usdc)));
    assertFalse(vendingMachine.isTokenAccepted(address(usdt)));
    assertFalse(vendingMachine.isTokenAccepted(address(dai)));

    // it adds new accepted tokens
    assertTrue(vendingMachine.isTokenAccepted(newToken));
  }

  // VendFromTrack tests
  function test_VendFromTrackWhenTokenIsNotAccepted() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vendingMachine.setTrackPrice(0, 2e18);
    
    address[] memory emptyTokens = new address[](0);
    vendingMachine.configurePaymentTokens(emptyTokens);
    vm.stopPrank();

    vm.prank(customer);
    // it reverts with TokenNotAccepted
    vm.expectRevert(IVendingMachine.TokenNotAccepted.selector);
    vendingMachine.vendFromTrack(0, address(usdc), customer);
  }

  function test_VendFromTrackWhenTrackIdIsInvalid() external {
    vm.prank(customer);
    // it reverts with InvalidTrackId
    vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
    vendingMachine.vendFromTrack(DEFAULT_NUM_TRACKS, address(usdc), customer);
  }

  function test_VendFromTrackWhenPriceIsNotSet() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vm.stopPrank();

    usdc.mint(customer, 10e18);

    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), 10e18);

    // it reverts with PriceNotSet
    vm.expectRevert(IVendingMachine.PriceNotSet.selector);
    vendingMachine.vendFromTrack(0, address(usdc), customer);
    vm.stopPrank();
  }

  function test_VendFromTrackWhenTrackHasInsufficientStock() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 1);
    vendingMachine.setTrackPrice(0, 2e18);
    vm.stopPrank();

    uint256 price = 2e18;
    usdc.mint(customer, price * 2);

    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), price * 2);

    vendingMachine.vendFromTrack(0, address(usdc), customer);

    // it reverts with InsufficientStock
    vm.expectRevert(IVendingMachine.InsufficientStock.selector);
    vendingMachine.vendFromTrack(0, address(usdc), customer);
    vm.stopPrank();
  }

  function test_VendFromTrackWhenRecipientIsZeroAddress() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vendingMachine.setTrackPrice(0, 2e18);
    vm.stopPrank();

    uint256 price = 2e18;
    usdc.mint(customer, price);

    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), price);

    uint256 totalSupplyBefore = voteToken.totalSupply();
    uint256 balanceBefore = usdc.balanceOf(address(vendingMachine));

    // it emits ItemVended event
    vm.expectEmit(true, true, false, true);
    emit ItemVended(0, customer, address(usdc), 1, price);

    vendingMachine.vendFromTrack(0, address(usdc), address(0));

    // it transfers payment from buyer
    assertEq(usdc.balanceOf(customer), 0);
    assertEq(usdc.balanceOf(address(vendingMachine)), balanceBefore + price);

    // it decreases stock
    assertEq(vendingMachine.getTrackInventory(0), 39);

    // it does not mint vote tokens
    assertEq(voteToken.totalSupply(), totalSupplyBefore);

    vm.stopPrank();
  }

  function test_VendFromTrackWhenAllConditionsAreMet() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vendingMachine.setTrackPrice(0, 2e18);
    vm.stopPrank();

    uint256 price = 2e18;
    usdc.mint(customer, price);

    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), price);

    // it emits ItemVended event
    vm.expectEmit(true, true, false, true);
    emit ItemVended(0, customer, address(usdc), 1, price);

    uint256 paidAmount = vendingMachine.vendFromTrack(0, address(usdc), customer);

    // it returns the paid amount
    assertEq(paidAmount, price);

    // it transfers payment from buyer
    assertEq(usdc.balanceOf(customer), 0);
    assertEq(usdc.balanceOf(address(vendingMachine)), price);

    // it decreases stock
    assertEq(vendingMachine.getTrackInventory(0), 39);

    // it mints vote tokens to recipient
    assertEq(voteToken.balanceOf(customer), price);

    vm.stopPrank();
  }

  // WithdrawRevenue tests
  modifier whenCalledByTreasury() {
    vm.startPrank(treasury);
    _;
    vm.stopPrank();
  }

  function test_WithdrawRevenueWhenCallerDoesNotHaveTREASURY_ROLE() external {
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdc);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1e18;

    // it reverts with AccessControlUnauthorizedAccount
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonTreasury, vendingMachine.TREASURY_ROLE())
    );
    vm.prank(nonTreasury);
    vendingMachine.withdrawRevenue(tokens, treasury, amounts);
  }

  function test_WithdrawRevenueWhenArraysHaveMismatchedLengths() external whenCalledByTreasury {
    address[] memory tokens = new address[](2);
    tokens[0] = address(usdc);
    tokens[1] = address(usdt);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1e18;

    // it reverts with ArrayLengthMismatch
    vm.expectRevert(IVendingMachine.ArrayLengthMismatch.selector);
    vendingMachine.withdrawRevenue(tokens, treasury, amounts);
  }

  function test_WithdrawRevenueWhenContractHasInsufficientBalance() external {
    // Setup: make a purchase first
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vendingMachine.setTrackPrice(0, 1e18);
    vm.stopPrank();

    usdc.mint(customer, 1e18);
    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), 1e18);
    vendingMachine.vendFromTrack(0, address(usdc), customer);
    vm.stopPrank();

    address[] memory tokens = new address[](1);
    tokens[0] = address(usdc);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 2e18; // More than available

    vm.prank(treasury);
    // it reverts with transfer failure
    vm.expectRevert();
    vendingMachine.withdrawRevenue(tokens, treasury, amounts);
  }

  function test_WithdrawRevenueWhenParametersAreValid() external {
    // Setup: make a purchase first
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Soda', imageURI: 'ipfs://soda'});
    vendingMachine.loadTrack(0, product, 40);
    vendingMachine.setTrackPrice(0, 2e18);
    vm.stopPrank();

    uint256 price = 2e18;
    usdc.mint(customer, price);

    vm.startPrank(customer);
    usdc.approve(address(vendingMachine), price);
    vendingMachine.vendFromTrack(0, address(usdc), customer);
    vm.stopPrank();

    uint256 balanceBefore = usdc.balanceOf(treasury);

    address[] memory withdrawTokens = new address[](1);
    withdrawTokens[0] = address(usdc);
    uint256[] memory withdrawAmounts = new uint256[](1);
    withdrawAmounts[0] = price;

    vm.prank(treasury);

    // it emits RevenueWithdrawn event
    vm.expectEmit(true, true, false, true);
    emit RevenueWithdrawn(address(usdc), treasury, price);

    vendingMachine.withdrawRevenue(withdrawTokens, treasury, withdrawAmounts);

    // it transfers specified amounts to recipient
    assertEq(usdc.balanceOf(treasury), balanceBefore + price);
    assertEq(usdc.balanceOf(address(vendingMachine)), 0);
  }

  // GetTrack tests
  function test_GetTrackWhenTrackIdIsInvalid() external view {
    // it returns empty track for invalid ID (no validation in view function)
    IVendingMachine.Track memory track = vendingMachine.getTrack(DEFAULT_NUM_TRACKS);
    assertEq(track.trackId, 0);
    assertEq(track.product.name, "");
    assertEq(track.product.imageURI, "");
    assertEq(track.stock, 0);
    assertEq(track.price, 0);
  }

  function test_GetTrackWhenTrackIdIsValid() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Test Product', imageURI: 'ipfs://test'});
    vendingMachine.loadTrack(1, product, 25);
    vendingMachine.setTrackPrice(1, 5e18);
    vm.stopPrank();

    // it returns the track details
    IVendingMachine.Track memory track = vendingMachine.getTrack(1);
    assertEq(track.trackId, 1);
    assertEq(track.product.name, 'Test Product');
    assertEq(track.product.imageURI, 'ipfs://test');
    assertEq(track.stock, 25);
    assertEq(track.price, 5e18);
  }

  // GetTrackInventory tests
  function test_GetTrackInventoryWhenTrackIdIsInvalid() external view {
    // it returns 0 for invalid track ID (no validation in view function)
    uint256 inventory = vendingMachine.getTrackInventory(DEFAULT_NUM_TRACKS);
    assertEq(inventory, 0);
  }

  function test_GetTrackInventoryWhenTrackIdIsValid() external {
    vm.startPrank(operator);
    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Test Product', imageURI: 'ipfs://test'});
    vendingMachine.loadTrack(2, product, 35);
    vm.stopPrank();

    // it returns the stock amount
    uint256 inventory = vendingMachine.getTrackInventory(2);
    assertEq(inventory, 35);
  }

  // GetAllTracks tests
  function test_GetAllTracksWhenCalled() external {
    vm.startPrank(operator);
    for (uint8 i = 0; i < DEFAULT_NUM_TRACKS; i++) {
      IVendingMachine.Product memory product = IVendingMachine.Product({
        name: string(abi.encodePacked('Product', i)),
        imageURI: string(abi.encodePacked('ipfs://', i))
      });
      vendingMachine.loadTrack(i, product, 10 + i);
      vendingMachine.setTrackPrice(i, uint256(i + 1) * 1e18);
    }
    vm.stopPrank();

    // it returns array of all tracks
    IVendingMachine.Track[] memory allTracks = vendingMachine.getAllTracks();

    assertEq(allTracks.length, DEFAULT_NUM_TRACKS);
    for (uint8 i = 0; i < DEFAULT_NUM_TRACKS; i++) {
      assertEq(allTracks[i].trackId, i);
      assertEq(allTracks[i].price, uint256(i + 1) * 1e18);
      assertEq(allTracks[i].stock, 10 + i);
    }
  }

  // IsTokenAccepted tests
  function test_IsTokenAcceptedWhenCalledWithTokenAddress() external view {
    // it returns acceptance status
    assertTrue(vendingMachine.isTokenAccepted(address(usdc)));
    assertTrue(vendingMachine.isTokenAccepted(address(usdt)));
    assertTrue(vendingMachine.isTokenAccepted(address(dai)));
    assertFalse(vendingMachine.isTokenAccepted(address(0x123)));
  }

  // GetAcceptedTokens tests
  function test_GetAcceptedTokensWhenCalled() external view {
    // it returns array of accepted tokens
    address[] memory tokens = vendingMachine.getAcceptedTokens();

    assertEq(tokens.length, 3);
    assertEq(tokens[0], address(usdc));
    assertEq(tokens[1], address(usdt));
    assertEq(tokens[2], address(dai));
  }
}