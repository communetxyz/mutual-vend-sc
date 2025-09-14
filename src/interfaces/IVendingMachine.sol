// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVendingMachine
 * @notice Interface for a blockchain-based vending machine with track management and token payments
 * @dev Supports multiple tracks with sequential dispensing, ERC20 token payments, and participation token issuance
 */
interface IVendingMachine {
  /**
   * @notice Product information structure
   * @param name Product name
   * @param imageURI IPFS or HTTP URI for product image
   */
  struct Product {
    string name;
    string imageURI;
  }

  /**
   * @notice Track information structure
   * @param trackId Unique identifier for the track (0 to NUM_TRACKS-1)
   * @param product Product information for this track
   * @param price Price in wei (1e18 = $1)
   * @param stock Current stock level in the track
   */
  struct Track {
    uint8 trackId;
    Product product;
    uint256 price;
    uint256 stock;
  }

  // Custom errors
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

  // Events
  /**
   * @notice Emitted when a track is loaded with products
   * @param trackId The track that was loaded
   * @param itemName Name of the product loaded
   * @param imageURI Image URI of the product
   * @param quantity Stock quantity loaded
   */
  event TrackLoaded(uint8 indexed trackId, string itemName, string imageURI, uint256 quantity);

  /**
   * @notice Emitted when a track is restocked
   * @param trackId The track that was restocked
   * @param additionalStock Amount of stock added
   */
  event TrackRestocked(uint8 indexed trackId, uint256 additionalStock);

  /**
   * @notice Emitted when a track's price is set
   * @param trackId The track whose price was set
   * @param dollarPrice New price in wei (1e18 = $1)
   */
  event TrackPriceSet(uint8 indexed trackId, uint256 dollarPrice);

  /**
   * @notice Emitted when token acceptance status changes
   * @param token The token address
   * @param accepted Whether the token is now accepted
   */
  event TokenAcceptanceUpdated(address indexed token, bool accepted);

  /**
   * @notice Emitted when an item is vended
   * @param trackId The track from which the item was vended
   * @param customer The address that purchased the item
   * @param token The payment token used
   * @param quantity Number of items vended (always 1 in current implementation)
   * @param amount Total payment amount in wei
   */
  event ItemVended(uint8 indexed trackId, address indexed customer, address token, uint256 quantity, uint256 amount);

  /**
   * @notice Emitted when revenue is withdrawn
   * @param token The token withdrawn
   * @param to The recipient address
   * @param amount Amount withdrawn
   */
  event RevenueWithdrawn(address indexed token, address indexed to, uint256 amount);

  // Functions
  /**
   * @notice Load a track with a product and initial stock
   * @dev Only callable by OPERATOR_ROLE. If product is empty, preserves existing product
   * @param trackId Track to load (0 to NUM_TRACKS-1)
   * @param product Product information
   * @param stock Initial stock level (must not exceed MAX_STOCK_PER_TRACK)
   */
  function loadTrack(uint8 trackId, Product memory product, uint256 stock) external;

  /**
   * @notice Batch load multiple tracks
   * @dev Only callable by OPERATOR_ROLE. Arrays must be same length
   * @param trackIds Array of track IDs to load
   * @param products Array of products corresponding to tracks
   * @param stocks Array of stock levels corresponding to tracks
   */
  function loadMultipleTracks(
    uint8[] calldata trackIds,
    Product[] calldata products,
    uint256[] calldata stocks
  ) external;

  /**
   * @notice Add stock to an existing track
   * @dev Only callable by OPERATOR_ROLE
   * @param trackId Track to restock
   * @param additionalStock Amount to add (new total must not exceed MAX_STOCK_PER_TRACK)
   */
  function restockTrack(uint8 trackId, uint256 additionalStock) external;

  /**
   * @notice Set the price for a track
   * @dev Only callable by OPERATOR_ROLE. Price is in wei where 1e18 = $1
   * @param trackId Track to set price for
   * @param dollarPrice Price in wei (1e18 = $1)
   */
  function setTrackPrice(uint8 trackId, uint256 dollarPrice) external;

  /**
   * @notice Configure which payment tokens are accepted
   * @dev Only callable by OPERATOR_ROLE. Replaces all existing accepted tokens
   * @param tokens Array of ERC20 token addresses to accept
   */
  function configurePaymentTokens(address[] calldata tokens) external;

  /**
   * @notice Purchase an item from a specific track
   * @dev Transfers payment token, decrements stock, and mints vote tokens
   * @param trackId Track to vend from
   * @param token Payment token to use (must be accepted)
   * @param recipient Address to receive vote tokens (can be address(0) to skip minting)
   * @return Amount paid in wei
   */
  function vendFromTrack(uint8 trackId, address token, address recipient) external returns (uint256);

  /**
   * @notice Withdraw accumulated revenue
   * @dev Only callable by TREASURY_ROLE. Arrays must be same length
   * @param tokens Array of token addresses to withdraw
   * @param to Recipient address
   * @param amounts Array of amounts to withdraw for each token
   */
  function withdrawRevenue(address[] calldata tokens, address to, uint256[] calldata amounts) external;

  /**
   * @notice Get complete track information
   * @param trackId Track to query
   * @return Track structure with all information
   */
  function getTrack(uint8 trackId) external view returns (Track memory);

  /**
   * @notice Get current stock level for a track
   * @param trackId Track to query
   * @return Current stock level
   */
  function getTrackInventory(uint8 trackId) external view returns (uint256);

  /**
   * @notice Check if a token is accepted for payment
   * @param token Token address to check
   * @return True if token is accepted
   */
  function isTokenAccepted(address token) external view returns (bool);

  /**
   * @notice Get all track information
   * @return Array of all tracks
   */
  function getAllTracks() external view returns (Track[] memory);
}
