// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVendingMachine} from "../interfaces/IVendingMachine.sol";
import {IVoteToken} from "../interfaces/IVoteToken.sol";

contract VendingMachine is IVendingMachine, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint8 public immutable NUM_TRACKS;
    IVoteToken public immutable voteToken;

    mapping(uint8 => Track) private tracks;
    mapping(address => bool) private acceptedTokens;
    mapping(uint8 => uint256) private trackInventory;

    constructor(uint8 _numTracks, address _voteToken) {
        if (_numTracks == 0) revert InvalidTrackCount();
        if (_voteToken == address(0)) revert ZeroAddress();
        
        NUM_TRACKS = _numTracks;
        voteToken = IVoteToken(_voteToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
    }

    function loadTrack(
        uint8 trackId,
        Product memory product,
        uint256 initialStock
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        _validateProduct(product);
        if (initialStock == 0) revert InvalidStock();
        
        tracks[trackId] = Track({
            trackId: trackId,
            product: product
        });
        trackInventory[trackId] = initialStock;
        
        emit TrackLoaded(trackId, product.name, product.imageURI, initialStock);
    }

    function loadMultipleTracks(
        uint8[] calldata trackIds,
        Product[] calldata products,
        uint256[] calldata initialStocks
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 length = trackIds.length;
        if (length != products.length || length != initialStocks.length) {
            revert ArrayLengthMismatch();
        }
        
        for (uint256 i = 0; i < length; i++) {
            _validateTrackId(trackIds[i]);
            _validateProduct(products[i]);
            if (initialStocks[i] == 0) revert InvalidStock();
            
            tracks[trackIds[i]] = Track({
                trackId: trackIds[i],
                product: products[i]
            });
            trackInventory[trackIds[i]] = initialStocks[i];
            
            emit TrackLoaded(trackIds[i], products[i].name, products[i].imageURI, initialStocks[i]);
        }
    }

    function restockTrack(
        uint8 trackId,
        uint256 additionalStock
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        if (additionalStock == 0) revert InvalidStock();
        if (bytes(tracks[trackId].product.name).length == 0) revert TrackNotConfigured();
        
        trackInventory[trackId] += additionalStock;
        
        emit TrackRestocked(trackId, additionalStock);
    }

    function setTrackPrice(
        uint8 trackId,
        uint256 dollarPrice
    ) external onlyRole(OPERATOR_ROLE) {
        _validateTrackId(trackId);
        if (dollarPrice == 0) revert InvalidPrice();
        if (bytes(tracks[trackId].product.name).length == 0) revert TrackNotConfigured();
        
        tracks[trackId].product.price = dollarPrice;
        
        emit TrackPriceSet(trackId, dollarPrice);
    }

    function configurePaymentTokens(
        address[] calldata tokens
    ) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[i] == tokens[j]) revert DuplicateToken();
            }
        }
        
        address[] memory previousTokens = _getAcceptedTokens();
        for (uint256 i = 0; i < previousTokens.length; i++) {
            acceptedTokens[previousTokens[i]] = false;
            emit TokenAcceptanceUpdated(previousTokens[i], false);
        }
        
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
        _validateTrackId(trackId);
        if (!acceptedTokens[token]) revert TokenNotAccepted();
        if (recipient == address(0)) revert ZeroAddress();
        
        Track memory track = tracks[trackId];
        if (bytes(track.product.name).length == 0) revert TrackNotConfigured();
        if (track.product.price == 0) revert PriceNotSet();
        if (trackInventory[trackId] == 0) revert InsufficientStock();
        
        uint256 price = track.product.price * 1e6;
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), price);
        
        trackInventory[trackId]--;
        
        voteToken.mint(recipient, price);
        
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
        _validateTrackId(trackId);
        return tracks[trackId];
    }

    function getTrackInventory(uint8 trackId) external view returns (uint256) {
        _validateTrackId(trackId);
        return trackInventory[trackId];
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

    function _validateTrackId(uint8 trackId) private view {
        if (trackId >= NUM_TRACKS) revert InvalidTrackId();
    }

    function _validateProduct(Product memory product) private pure {
        if (bytes(product.name).length == 0) revert InvalidProductName();
        if (product.price == 0) revert InvalidPrice();
    }

    function _getAcceptedTokens() private view returns (address[] memory) {
        address[] memory tokens = new address[](100);
        uint256 count = 0;
        
        address[] memory commonTokens = new address[](3);
        commonTokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        commonTokens[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        commonTokens[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        
        for (uint256 i = 0; i < commonTokens.length; i++) {
            if (acceptedTokens[commonTokens[i]]) {
                tokens[count++] = commonTokens[i];
            }
        }
        
        assembly {
            mstore(tokens, count)
        }
        
        return tokens;
    }
}
