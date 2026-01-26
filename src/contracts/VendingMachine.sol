// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITreasuryDistributor} from '../interfaces/ITreasuryDistributor.sol';
import {IVendingMachine} from '../interfaces/IVendingMachine.sol';
import {VoteToken} from './VoteToken.sol';
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract VendingMachine is IVendingMachine, ReentrancyGuard, AccessControl {
  using SafeERC20 for IERC20;

  /// @inheritdoc IVendingMachine
  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
  /// @inheritdoc IVendingMachine
  bytes32 public constant TREASURY_ROLE = keccak256('TREASURY_ROLE');

  /// @inheritdoc IVendingMachine
  uint8 public immutable NUM_TRACKS;
  /// @inheritdoc IVendingMachine
  uint256 public immutable MAX_STOCK_PER_TRACK;
  /// @notice Vote token issued to purchasers
  VoteToken public immutable voteToken;
  /// @inheritdoc IVendingMachine
  address[] public acceptedTokenList;
  /// @inheritdoc IVendingMachine
  address public treasuryDistributor;

  mapping(uint8 => Track) private tracks;
  mapping(address => bool) private acceptedTokens;

  /// @notice Initializes the vending machine with tracks, tokens, and optional treasury distributor
  /// @param _numTracks Number of tracks in the machine
  /// @param _maxStockPerTrack Maximum stock per track
  /// @param _voteTokenName Name for the vote token
  /// @param _voteTokenSymbol Symbol for the vote token
  /// @param _initialAcceptedTokens Initial list of accepted payment tokens
  /// @param _initialProducts Initial products to load into tracks
  /// @param _initialStocks Initial stock levels for tracks
  /// @param _initialPrices Initial prices for tracks
  /// @param _treasuryDistributor Optional treasury distributor address (can be zero address)
  constructor(
    uint8 _numTracks,
    uint256 _maxStockPerTrack,
    string memory _voteTokenName,
    string memory _voteTokenSymbol,
    address[] memory _initialAcceptedTokens,
    Product[] memory _initialProducts,
    uint256[] memory _initialStocks,
    uint256[] memory _initialPrices,
    address _treasuryDistributor
  ) {
    if (_numTracks == 0) revert InvalidTrackCount();
    if (_maxStockPerTrack == 0) revert InvalidStock();

    NUM_TRACKS = _numTracks;
    MAX_STOCK_PER_TRACK = _maxStockPerTrack;

    // Deploy vote token and grant minter role to this contract
    voteToken = new VoteToken(_voteTokenName, _voteTokenSymbol);
    voteToken.grantRole(voteToken.MINTER_ROLE(), address(this));

    // Initialize tracks with products if provided
    for (uint8 i = 0; i < _numTracks; i++) {
      tracks[i].trackId = i;

      // Initialize with products if provided
      if (i < _initialProducts.length) {
        tracks[i].product = _initialProducts[i];

        if (i < _initialStocks.length) {
          if (_initialStocks[i] > _maxStockPerTrack) revert InvalidStock();
          tracks[i].stock = _initialStocks[i];
        }

        if (i < _initialPrices.length && _initialPrices[i] != 0) {
          tracks[i].price = _initialPrices[i];
        }
      }
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

    // Set treasury distributor if provided (can be EOA or contract)
    if (_treasuryDistributor != address(0)) {
      treasuryDistributor = _treasuryDistributor;
      _grantRole(TREASURY_ROLE, _treasuryDistributor);
    }
  }

  function loadTrack(uint8 trackId, Product memory product, uint256 stock) external onlyRole(OPERATOR_ROLE) {
    _validateTrackId(trackId);
    _loadTrack(trackId, product, stock);
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
      _loadTrack(trackIds[i], products[i], stocks[i]);
    }
  }

  function restockTrack(uint8 trackId, uint256 additionalStock) external onlyRole(OPERATOR_ROLE) {
    _validateTrackId(trackId);
    if (additionalStock == 0) revert InvalidStock();

    uint256 newStock = tracks[trackId].stock + additionalStock;
    if (newStock > MAX_STOCK_PER_TRACK) revert InvalidStock();

    tracks[trackId].stock = newStock;

    emit TrackRestocked(trackId, additionalStock);
  }

  function setTrackPrice(uint8 trackId, uint256 dollarPrice) external onlyRole(OPERATOR_ROLE) {
    _validateTrackId(trackId);
    if (dollarPrice == 0) revert InvalidPrice();

    tracks[trackId].price = dollarPrice;

    emit TrackPriceSet(trackId, dollarPrice);
  }

  function configurePaymentTokens(address[] calldata tokens) external onlyRole(OPERATOR_ROLE) {
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

  /// @inheritdoc IVendingMachine
  function setTreasuryDistributor(address _treasuryDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_treasuryDistributor == address(0)) revert ZeroAddress();

    // Revoke role from previous treasury distributor
    if (treasuryDistributor != address(0)) {
      _revokeRole(TREASURY_ROLE, treasuryDistributor);
    }

    treasuryDistributor = _treasuryDistributor;

    // Grant TREASURY_ROLE to the new distributor (can be EOA or contract)
    _grantRole(TREASURY_ROLE, _treasuryDistributor);
  }

  function vendFromTrack(uint8 trackId, address token, address recipient) external nonReentrant returns (uint256) {
    _validateTrackId(trackId);
    if (!acceptedTokens[token]) revert TokenNotAccepted();

    Track storage track = tracks[trackId];
    if (track.stock == 0) revert InsufficientStock();
    if (track.price == 0) revert PriceNotSet();

    uint256 price = track.price;

    IERC20(token).safeTransferFrom(msg.sender, address(this), price);

    track.stock--;

    // Mint vote tokens to recipient
    if (recipient != address(0)) {
      voteToken.mint(recipient, price);
    }

    // Try to notify treasury distributor of purchase (if it's a contract)
    if (treasuryDistributor != address(0)) {
      // Check if treasury is a contract before trying to call it
      address treasury = treasuryDistributor;
      uint256 codeSize;
      assembly {
        codeSize := extcodesize(treasury)
      }

      if (codeSize > 0) {
        // It's a contract, try to notify it
        try ITreasuryDistributor(treasury).onPurchase(recipient, price) {
        // Successfully notified
        }
          catch {
          // Silent fail - enables EOA treasury compatibility
        }
      }
      // If it's an EOA (codeSize == 0), we simply don't call it
    }

    emit ItemVended(trackId, msg.sender, token, 1, price);

    return price;
  }

  function withdrawRevenue(address to)
    external
    onlyRole(TREASURY_ROLE)
    returns (address[] memory tokens, uint256[] memory amounts)
  {
    if (to == address(0)) revert ZeroAddress();

    tokens = acceptedTokenList;
    amounts = new uint256[](tokens.length);

    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
      if (balance > 0) {
        amounts[i] = balance;
        IERC20(tokens[i]).safeTransfer(to, balance);
        emit RevenueWithdrawn(tokens[i], to, balance);
      }
    }

    return (tokens, amounts);
  }

  function getTrack(uint8 trackId) external view returns (Track memory) {
    return tracks[trackId];
  }

  function getTrackInventory(uint8 trackId) external view returns (uint256) {
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

  function _loadTrack(uint8 trackId, Product memory product, uint256 stock) private {
    if (stock > MAX_STOCK_PER_TRACK) revert InvalidStock();

    // Only overwrite product if not empty
    if (bytes(product.name).length > 0 || bytes(product.imageURI).length > 0) {
      tracks[trackId].product = product;
    }
    tracks[trackId].stock = stock;

    // Emit event with actual track product
    Product memory actualProduct = tracks[trackId].product;
    emit TrackLoaded(trackId, actualProduct.name, actualProduct.imageURI, stock);
  }
}
