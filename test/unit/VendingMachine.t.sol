// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
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
    
    function setUp() public {
        vm.startPrank(owner);
        
        voteToken = new VoteToken("Vending Machine Token", "VMT");
        vendingMachine = new VendingMachine(NUM_TRACKS, address(voteToken));
        
        voteToken.grantRole(voteToken.MINTER_ROLE(), address(vendingMachine));
        
        vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), operator);
        vendingMachine.grantRole(vendingMachine.TREASURY_ROLE(), treasury);
        
        usdc = new MockStablecoin("USD Coin", "USDC");
        usdt = new MockStablecoin("Tether", "USDT");
        dai = new MockStablecoin("Dai", "DAI");
        
        vm.stopPrank();
    }
    
    function test_Constructor() public {
        assertEq(vendingMachine.NUM_TRACKS(), NUM_TRACKS);
        assertEq(address(vendingMachine.voteToken()), address(voteToken));
    }
    
    function test_LoadTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        
        vendingMachine.loadTrack(0, product, 100);
        
        IVendingMachine.Track memory track = vendingMachine.getTrack(0);
        assertEq(track.trackId, 0);
        assertEq(track.product.name, "Soda");
        assertEq(track.product.imageURI, "ipfs://soda");
        assertEq(track.product.price, 2);
        assertEq(vendingMachine.getTrackInventory(0), 100);
        
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
            imageURI: "ipfs://soda",
            price: 2
        });
        products[1] = IVendingMachine.Product({
            name: "Chips",
            imageURI: "ipfs://chips",
            price: 3
        });
        
        uint256[] memory stocks = new uint256[](2);
        stocks[0] = 100;
        stocks[1] = 50;
        
        vendingMachine.loadMultipleTracks(trackIds, products, stocks);
        
        assertEq(vendingMachine.getTrack(0).product.name, "Soda");
        assertEq(vendingMachine.getTrack(1).product.name, "Chips");
        assertEq(vendingMachine.getTrackInventory(0), 100);
        assertEq(vendingMachine.getTrackInventory(1), 50);
        
        vm.stopPrank();
    }
    
    function test_ConfigurePaymentTokens() public {
        vm.startPrank(operator);
        
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        tokens[2] = address(dai);
        
        vendingMachine.configurePaymentTokens(tokens);
        
        assertTrue(vendingMachine.isTokenAccepted(address(usdc)));
        assertTrue(vendingMachine.isTokenAccepted(address(usdt)));
        assertTrue(vendingMachine.isTokenAccepted(address(dai)));
        
        vm.stopPrank();
    }
    
    function test_VendFromTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 100);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vendingMachine.configurePaymentTokens(tokens);
        
        vm.stopPrank();
        
        uint256 price = 2e6;
        usdc.mint(customer, price);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), price);
        
        uint256 paidAmount = vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        assertEq(paidAmount, price);
        assertEq(vendingMachine.getTrackInventory(0), 99);
        assertEq(usdc.balanceOf(customer), 0);
        assertEq(usdc.balanceOf(address(vendingMachine)), price);
        assertEq(voteToken.balanceOf(customer), price);
        
        vm.stopPrank();
    }
    
    function test_RestockTrack() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 10);
        
        vendingMachine.restockTrack(0, 50);
        
        assertEq(vendingMachine.getTrackInventory(0), 60);
        
        vm.stopPrank();
    }
    
    function test_SetTrackPrice() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 100);
        
        vendingMachine.setTrackPrice(0, 3);
        
        assertEq(vendingMachine.getTrack(0).product.price, 3);
        
        vm.stopPrank();
    }
    
    function test_WithdrawRevenue() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 100);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vendingMachine.configurePaymentTokens(tokens);
        
        vm.stopPrank();
        
        uint256 price = 2e6;
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
                imageURI: string(abi.encodePacked("ipfs://", i)),
                price: uint256(i + 1)
            });
            vendingMachine.loadTrack(i, product, 100);
        }
        
        vm.stopPrank();
        
        IVendingMachine.Track[] memory allTracks = vendingMachine.getAllTracks();
        
        assertEq(allTracks.length, NUM_TRACKS);
        for (uint8 i = 0; i < NUM_TRACKS; i++) {
            assertEq(allTracks[i].trackId, i);
            assertEq(allTracks[i].product.price, uint256(i + 1));
        }
    }
    
    function testRevert_InvalidTrackId() public {
        vm.expectRevert(IVendingMachine.InvalidTrackId.selector);
        vendingMachine.getTrack(NUM_TRACKS);
    }
    
    function testRevert_TokenNotAccepted() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 100);
        
        vm.stopPrank();
        
        vm.prank(customer);
        vm.expectRevert(IVendingMachine.TokenNotAccepted.selector);
        vendingMachine.vendFromTrack(0, address(usdc), customer);
    }
    
    function testRevert_InsufficientStock() public {
        vm.startPrank(operator);
        
        IVendingMachine.Product memory product = IVendingMachine.Product({
            name: "Soda",
            imageURI: "ipfs://soda",
            price: 2
        });
        vendingMachine.loadTrack(0, product, 1);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vendingMachine.configurePaymentTokens(tokens);
        
        vm.stopPrank();
        
        uint256 price = 2e6;
        usdc.mint(customer, price * 2);
        
        vm.startPrank(customer);
        usdc.approve(address(vendingMachine), price * 2);
        
        vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        vm.expectRevert(IVendingMachine.InsufficientStock.selector);
        vendingMachine.vendFromTrack(0, address(usdc), customer);
        
        vm.stopPrank();
    }
}