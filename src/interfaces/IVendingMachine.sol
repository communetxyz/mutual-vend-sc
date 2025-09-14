// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVendingMachine {
    struct Product {
        string name;
        string imageURI;
        uint256 price;
    }

    struct Track {
        uint8 trackId;
        Product product;
    }

    error InvalidTrackId();
    error InvalidTrackCount();
    error InvalidProductName();
    error InvalidPrice();
    error InvalidStock();
    error InvalidAmount();
    error TrackNotConfigured();
    error PriceNotSet();
    error InsufficientStock();
    error InsufficientBalance();
    error TokenNotAccepted();
    error ZeroAddress();
    error DuplicateToken();
    error ArrayLengthMismatch();

    event TrackLoaded(uint8 indexed trackId, string itemName, string imageURI, uint256 quantity);
    event TrackRestocked(uint8 indexed trackId, uint256 additionalStock);
    event TrackPriceSet(uint8 indexed trackId, uint256 dollarPrice);
    event TokenAcceptanceUpdated(address indexed token, bool accepted);
    event ItemVended(uint8 indexed trackId, address indexed customer, address token, uint256 quantity, uint256 amount);
    event RevenueWithdrawn(address indexed token, address indexed to, uint256 amount);

    function loadTrack(uint8 trackId, Product memory product, uint256 initialStock) external;
    function loadMultipleTracks(uint8[] calldata trackIds, Product[] calldata products, uint256[] calldata initialStocks) external;
    function restockTrack(uint8 trackId, uint256 additionalStock) external;
    function setTrackPrice(uint8 trackId, uint256 dollarPrice) external;
    function configurePaymentTokens(address[] calldata tokens) external;
    function vendFromTrack(uint8 trackId, address token, address recipient) external returns (uint256);
    function withdrawRevenue(address token, address to, uint256 amount) external;
    function getTrack(uint8 trackId) external view returns (Track memory);
    function getTrackInventory(uint8 trackId) external view returns (uint256);
    function isTokenAccepted(address token) external view returns (bool);
    function getAllTracks() external view returns (Track[] memory);
}
