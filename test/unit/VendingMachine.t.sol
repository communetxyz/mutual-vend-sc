// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VendingMachine} from "../../src/contracts/VendingMachine.sol";
import {VoteToken} from "../../src/contracts/VoteToken.sol";
import {IVendingMachine} from "../../src/interfaces/IVendingMachine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStablecoin is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VendingMachineTest is Test {
    VendingMachine public vendingMachine;
    VoteToken public voteToken;
    MockStablecoin public usdc;
    MockStablecoin public usdt;
    MockStablecoin public dai;
    
    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public treasury = makeAddr("treasury");
    address public customer = makeAddr("customer");
    
    uint8 constant NUM_TRACKS = 3;
    uint256 constant MAX_STOCK = 50;
    
    function setUp() public {
        vm.startPrank(owner);
        
        usdc = new MockStablecoin("USD Coin", "USDC");
        usdt = new MockStablecoin("Tether", "USDT");
        dai = new MockStablecoin("Dai", "DAI");
        
        // Create initial accepted tokens
        address[] memory acceptedTokens = new address[](3);
        acceptedTokens[0] = address(usdc);
        acceptedTokens[1] = address(usdt);
        acceptedTokens[2] = address(dai);
        
        // Deploy vending machine with integrated vote token
        vendingMachine = new VendingMachine(
            NUM_TRACKS,
            MAX_STOCK,
            "Vending Machine Token",
            "VMT",
            acceptedTokens
        );
        
        voteToken = vendingMachine.voteToken();
        
        vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), operator);
        vendingMachine.grantRole(vendingMachine.TREASURY_ROLE(), treasury);
        
        vm.stopPrank();
    }
    
    function test_Constructor() public {
        assertEq(vendingMachine.NUM_TRACKS(), NUM_TRACKS);
        assertEq(vendingMachine.MAX_STOCK_PER_TRACK(), MAX_STOCK);
        assertNotEq(address(vendingMachine.voteToken()), address(0));
        assertTrue(vendingMachine.isTokenAccepted(address(usdc)));
        assertTrue(vendingMachine.isTokenAccepted(address(usdt)));
        assertTrue(vendingMachine.isTokenAccepted(address(dai)));
    }
    
    function test_LoadTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        
        vendingMachine.loadTrack(0, product, 10);
        vendingMachine.setTrackPrice(0, 2e18); // $2 in 18 decimals
        
        IVendingMachine.Track memory track = vendingMachine.getTrack(0);
        assertEq(track.trackId, 0);
        assertEq(track.product.name, "Soda");
        assertEq(track.product.imageURI, "ipfs://soda");
        assertEq(track.price, 2e18);
        assertEq(track.stock, 10);
        
        vm.stopPrank();
    }
    
    function test_LoadTrackOverwrite() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product1 = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        
        IVendingMachine.Product memory product2 = IVendingMachine.Product({
            name: "Water",
            imageURI: "ipfs://water"
        });
        
        vendingMachine.loadTrack(0, product1, 10);
        
        // Overwrite with new product
        vendingMachine.loadTrack(0, product2, 5);
        
        IVendingMachine.Track memory track = vendingMachine.getTrack(0);
        assertEq(track.product.name, "Water");
        assertEq(track.stock, 5);
        
        vm.stopPrank();
    }
    
    function test_LoadMultipleTracks() public {
        vm.startPrank(operator);
        
        uint8[] memory trackIds = new uint8[](2);
        trackIds[0] = 0;
        trackIds[1] = 1;
        
        IVendingMachine.Product[] memory products = new IVendingMachine.Product[](2);
        products[0] = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        products[1] = IVendingMachine.Product({
            name: "Chips",
            imageURI: "ipfs://chips"
        });
        
        uint256[] memory stocks = new uint256[](2);
        stocks[0] = 20;
        stocks[1] = 30;
        
        vendingMachine.loadMultipleTracks(trackIds, products, stocks);
        
        assertEq(vendingMachine.getTrack(0).product.name, "Soda");
        assertEq(vendingMachine.getTrack(1).product.name, "Chips");
        assertEq(vendingMachine.getTrack(0).stock, 20);
        assertEq(vendingMachine.getTrack(1).stock, 30);
        
        vm.stopPrank();
    }
    
    function test_ConfigurePaymentTokens() public {
        vm.startPrank(operator);
        
        // Create new tokens
        address newToken = address(new MockStablecoin("New", "NEW"));
        address[] memory tokens = new address[](1);
        tokens[0] = newToken;
        
        vendingMachine.configurePaymentTokens(tokens);
        
        // Old tokens should no longer be accepted
        assertFalse(vendingMachine.isTokenAccepted(address(usdc)));
        assertFalse(vendingMachine.isTokenAccepted(address(usdt)));
        assertFalse(vendingMachine.isTokenAccepted(address(dai)));
        
        // New token should be accepted
        assertTrue(vendingMachine.isTokenAccepted(newToken));
        
        vm.stopPrank();
    }
    
    function test_VendFromTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 40);
        vendingMachine.setTrackPrice(0, 2e18); // $2 in 18 decimals
        
        vm.stopPrank();
        
        uint256 price = 2e18;
        usdc.mint(customer, price);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), price);
        
        uint256 paidAmount = vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        assertEq(paidAmount, price);
        assertEq(vendingMachine.getTrackInventory(0), 39);
        assertEq(usdc.balanceOf(customer), 0);
        assertEq(usdc.balanceOf(address(vendingMachine)), price);
        assertEq(voteToken.balanceOf(customer), price);
        
        vm.stopPrank();
    }
    
    function test_VendFromTrackWithZeroRecipient() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 40);
        vendingMachine.setTrackPrice(0, 2e18);
        
        vm.stopPrank();
        
        uint256 price = 2e18;
        usdc.mint(customer, price);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), price);
        
        uint256 totalSupplyBefore = voteToken.totalSupply();
        
        // Vend with zero recipient (no vote tokens minted)
        vendingMachine.vendFromTrack(0, address(usdc), address(0));
        
        // Vote token supply should not change
        assertEq(voteToken.totalSupply(), totalSupplyBefore);
        assertEq(vendingMachine.getTrackInventory(0), 39);
        
        vm.stopPrank();
    }
    
    function test_RestockTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 10);
        
        vendingMachine.restockTrack(0, 20);
        
        assertEq(vendingMachine.getTrackInventory(0), 30);
        
        vm.stopPrank();
    }
    
    function test_RestockTrackExceedsMax() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 40);
        
        // Trying to restock beyond MAX_STOCK should revert
        vm.expectRevert(IVendingMachine.InvalidStock.selector);
        vendingMachine.restockTrack(0, 20); // 40 + 20 = 60 > 50
        
        vm.stopPrank();
    }
    
    function test_SetTrackPrice() public {
        vm.startPrank(operator);
        
        vendingMachine.setTrackPrice(0, 3e18); // $3 in 18 decimals
        
        assertEq(vendingMachine.getTrack(0).price, 3e18);
        
        vm.stopPrank();
    }
    
    function test_WithdrawRevenue() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
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
        
        vm.prank(treasury);
        vendingMachine.withdrawRevenue(address(usdc), treasury, price);
        
        assertEq(usdc.balanceOf(treasury), balanceBefore + price);
        assertEq(usdc.balanceOf(address(vendingMachine)), 0);
    }
    
    function test_GetAllTracks() public {
        vm.startPrank(operator);
        
        for (uint8 i = 0; i < NUM_TRACKS; i++) {
            IVendingMachine.Product memory product = IVendingMachine.Product({
                name: string(abi.encodePacked("Product", i)),
                imageURI: string(abi.encodePacked("ipfs://", i))
            });
            vendingMachine.loadTrack(i, product, 10 + i);
            vendingMachine.setTrackPrice(i, uint256(i + 1) * 1e18);
        }
        
        vm.stopPrank();
        
        IVendingMachine.Track[] memory allTracks = vendingMachine.getAllTracks();
        
        assertEq(allTracks.length, NUM_TRACKS);
        for (uint8 i = 0; i < NUM_TRACKS; i++) {
            assertEq(allTracks[i].trackId, i);
            assertEq(allTracks[i].price, uint256(i + 1) * 1e18);
            assertEq(allTracks[i].stock, 10 + i);
        }
    }
    
    function test_GetAcceptedTokens() public {
        address[] memory tokens = vendingMachine.getAcceptedTokens();
        
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(usdc));
        assertEq(tokens[1], address(usdt));
        assertEq(tokens[2], address(dai));
    }
    
    function testRevert_InvalidTrackIdOnLoad() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        
        vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
        vendingMachine.loadTrack(NUM_TRACKS, product, 10);
        
        vm.stopPrank();
    }
    
    function testRevert_TokenNotAccepted() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 40);
        vendingMachine.setTrackPrice(0, 2e18);
        
        // Clear accepted tokens
        address[] memory emptyTokens = new address[](0);
        vendingMachine.configurePaymentTokens(emptyTokens);
        
        vm.stopPrank();
        
        vm.prank(customer);
        vm.expectRevert(IVendingMachine.TokenNotAccepted.selector);
        vendingMachine.vendFromTrack(0, address(usdc), customer);
    }
    
    function testRevert_InsufficientStock() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 1);
        vendingMachine.setTrackPrice(0, 2e18);
        
        vm.stopPrank();
        
        uint256 price = 2e18;
        usdc.mint(customer, price * 2);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), price * 2);
        
        vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        vm.expectRevert(IVendingMachine.InsufficientStock.selector);
        vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        vm.stopPrank();
    }
    
    function testRevert_PriceNotSet() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        vendingMachine.loadTrack(0, product, 40);
        // Don't set price
        
        vm.stopPrank();
        
        usdc.mint(customer, 10e18);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), 10e18);
        
        vm.expectRevert(IVendingMachine.PriceNotSet.selector);
        vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        vm.stopPrank();
    }
    
    function testRevert_StockExceedsMax() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda"
        });
        
        vm.expectRevert(IVendingMachine.InvalidStock.selector);
        vendingMachine.loadTrack(0, product, MAX_STOCK + 1);
        
        vm.stopPrank();
    }
}