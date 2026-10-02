// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @notice Four independently opened compartments. One sale makes a compartment unavailable until restocked.
/// @dev A payment receipt is not evidence of hardware delivery. Direct BLE pilot requires supervision.
contract KSJVendV2 is ReentrancyGuard {
  using SafeERC20 for IERC20;
  uint8 public constant COMPARTMENTS = 4;
  IERC20 public immutable paymentToken;
  address public immutable owner;
  struct Slot { string name; uint256 price; bool available; }
  struct Order { address buyer; uint8 compartment; uint256 amount; bool refunded; }
  Slot[4] private slots;
  mapping(uint256 => Order) public orders;
  uint256 public nextOrderId = 1;
  event Purchased(uint256 indexed orderId, address indexed buyer, uint8 indexed compartment, uint256 amount);
  event Restocked(uint8 indexed compartment, string name, uint256 price, bool available);
  event Refunded(uint256 indexed orderId);
  error Unauthorized(); error InvalidSlot(); error InvalidConfig(); error Unavailable(); error PriceChanged(); error InvalidOrder();
  modifier onlyOwner() { if (msg.sender != owner) revert Unauthorized(); _; }
  constructor(address token, address operator) {
    if (token == address(0) || token.code.length == 0 || operator == address(0)) revert InvalidConfig();
    paymentToken = IERC20(token); owner = operator;
  }
  function getSlots() external view returns (Slot[4] memory) { return slots; }
  function configure(uint8 compartment, string calldata name, uint256 price, bool available) external onlyOwner {
    if (compartment >= 4) revert InvalidSlot();
    if (bytes(name).length == 0 || bytes(name).length > 120 || price == 0) revert InvalidConfig();
    slots[compartment] = Slot(name, price, available);
    emit Restocked(compartment, name, price, available);
  }
  function purchase(uint8 compartment, uint256 expectedPrice) external nonReentrant returns (uint256 id) {
    if (compartment >= 4) revert InvalidSlot();
    Slot storage slot = slots[compartment];
    if (!slot.available) revert Unavailable();
    if (expectedPrice != slot.price) revert PriceChanged();
    slot.available = false;
    id = nextOrderId++;
    orders[id] = Order(msg.sender, compartment, slot.price, false);
    paymentToken.safeTransferFrom(msg.sender, address(this), slot.price);
    emit Purchased(id, msg.sender, compartment, slot.price);
  }
  /// @notice Operator resolves a failed pickup. Does not reopen or restock the compartment.
  function refund(uint256 id) external onlyOwner nonReentrant {
    Order storage order = orders[id];
    if (order.buyer == address(0) || order.refunded) revert InvalidOrder();
    order.refunded = true;
    paymentToken.safeTransfer(order.buyer, order.amount);
    emit Refunded(id);
  }
  function withdraw(address recipient, uint256 amount) external onlyOwner nonReentrant {
    if (recipient == address(0)) revert InvalidConfig();
    paymentToken.safeTransfer(recipient, amount);
  }
}
