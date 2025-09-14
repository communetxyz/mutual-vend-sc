// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVendingMachine} from "../interfaces/IVendingMachine.sol";
import {VoteToken} from "./VoteToken.sol";

contract VendingMachine is IVendingMachine, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint8 public immutable NUM_TRACKS;
    uint256 public immutable MAX_STOCK_PER_TRACK;
    VoteToken public immutable voteToken;
    address[] public acceptedTokenList;

    mapping(uint8 => Track) private tracks;
    mapping(address => bool) private acceptedTokens;

    constructor(
        uint8 _numTracks,
        uint256 _maxStockPerTrack,
        string memory _voteTokenName,
        string memory _voteTokenSymbol,
        address[] memory _initialAcceptedTokens
    ) {
        if (_numTracks == 0) revert InvalidTrackCount();
        if (_maxStockPerTrack == 0) revert InvalidStock();
        
        NUM_TRACKS = _numTracks;
        MAX_STOCK_PER_TRACK = _maxStockPerTrack;
        
        // Deploy vote token and grant minter role to this contract
        voteToken = new VoteToken(_voteTokenName, _voteTokenSymbol);
        voteToken.grantRole(voteToken.MINTER_ROLE(), address(this));
        
        // Initialize tracks
        for (uint8 i = 0; i < _numTracks; i++) {
            tracks[i].trackId = i;
        }
        
        // Set initial accepted tokens
        acceptedTokenList = _initialAcceptedTokens;
        for (uint256 i = 0; i < _initialAcceptedTokens.length; i++) {
            if (_initialAcceptedTokens[i] == address(0)) revert ZeroAddress();
            acceptedTokens[_initialAcceptedTokens[i]] = true;
        }
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
    }

    function loadTrack(
        uint8 trackId,
        Product memory product,
        uint256 stock
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        if (stock > MAX_STOCK_PER_TRACK) revert InvalidStock();
        
        // Allow empty product to clear track, otherwise overwrite existing product
        tracks[trackId].product = product;
        tracks[trackId].stock = stock;
        
        emit TrackLoaded(trackId, product.name, product.imageURI, stock);
    }

    function loadMultipleTracks(
        uint8[] calldata trackIds,
        Product[] calldata products,
        uint256[] calldata stocks
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 length = trackIds.length;
        if (length != products.length || length != stocks.length) {
            revert ArrayLengthMismatch();
        }
        
        for (uint256 i = 0; i < length; i++) {
            _validateTrackId(trackIds[i]);
            if (stocks[i] > MAX_STOCK_PER_TRACK) revert InvalidStock();
            
            tracks[trackIds[i]].product = products[i];
            tracks[trackIds[i]].stock = stocks[i];
            
            emit TrackLoaded(trackIds[i], products[i].name, products[i].imageURI, stocks[i]);
        }
    }

    function restockTrack(
        uint8 trackId,
        uint256 additionalStock
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        if (additionalStock == 0) revert InvalidStock();
        
        uint256 newStock = tracks[trackId].stock + additionalStock;
        if (newStock > MAX_STOCK_PER_TRACK) revert InvalidStock();
        
        tracks[trackId].stock = newStock;
        
        emit TrackRestocked(trackId, additionalStock);
    }

    function setTrackPrice(
        uint8 trackId,
        uint256 dollarPrice
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        if (dollarPrice == 0) revert InvalidPrice();
        
        tracks[trackId].price = dollarPrice;
        
        emit TrackPriceSet(trackId, dollarPrice);
    }

    function configurePaymentTokens(
        address[] calldata tokens
    ) external onlyRole(OPERATOR_ROLE) {
        // Validate tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[i] == tokens[j]) revert DuplicateToken();
            }
        }
        
        // Clear existing accepted tokens
        for (uint256 i = 0; i < acceptedTokenList.length; i++) {
            acceptedTokens[acceptedTokenList[i]] = false;
            emit TokenAcceptanceUpdated(acceptedTokenList[i], false);
        }
        
        // Set new accepted tokens
        acceptedTokenList = tokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            acceptedTokens[tokens[i]] = true;
            emit TokenAcceptanceUpdated(tokens[i], true);
        }
    }

    function vendFromTrack(
        uint8 trackId,
        address token,
        address recipient
    ) external nonReentrant returns (uint256) {
        if (!acceptedTokens[token]) revert TokenNotAccepted();
        // Allow recipient to be 0 address for burning
        
        Track storage track = tracks[trackId];
        if (track.stock == 0) revert InsufficientStock();
        if (track.price == 0) revert PriceNotSet();
        
        // Price is already in 1e18 format
        uint256 price = track.price;
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), price);
        
        track.stock--;
        
        // Mint vote tokens to recipient (or 0 address for burn)
        if (recipient != address(0)) {
            voteToken.mint(recipient, price);
        }
        
        emit ItemVended(trackId, msg.sender, token, 1, price);
        
        return price;
    }

    function withdrawRevenue(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(TREASURY_ROLE) {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();
        
        IERC20(token).safeTransfer(to, amount);
        
        emit RevenueWithdrawn(token, to, amount);
    }

    function getTrack(uint8 trackId) external view returns (Track memory) {
        // No validation needed per comment
        return tracks[trackId];
    }

    function getTrackInventory(uint8 trackId) external view returns (uint256) {
        // No validation needed per comment
        return tracks[trackId].stock;
    }

    function isTokenAccepted(address token) external view returns (bool) {
        return acceptedTokens[token];
    }

    function getAllTracks() external view returns (Track[] memory) {
        Track[] memory allTracks = new Track[](NUM_TRACKS);
        for (uint8 i = 0; i < NUM_TRACKS; i++) {
            allTracks[i] = tracks[i];
        }
        return allTracks;
    }

    function getAcceptedTokens() external view returns (address[] memory) {
        return acceptedTokenList;
    }

    function _validateTrackId(uint8 trackId) private view {
        if (trackId >= NUM_TRACKS) revert InvalidTrackId();
    }
}