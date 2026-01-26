// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISlashingExtension} from '../interfaces/ISlashingExtension.sol';
import {IVendingMachine} from '../interfaces/IVendingMachine.sol';
import {VoteToken} from './VoteToken.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Initializable} from '@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol';
import {AccessControlUpgradeable} from '@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol';

/**
 * @title SlashingExtension
 * @notice Allows VMT token holders to slash stocker security deposits via majority vote
 * @dev Works alongside VendingMachine to enforce correct stocking behavior. Upgradeable via UUPS pattern.
 */
contract SlashingExtension is
  Initializable,
  ISlashingExtension,
  ReentrancyGuard,
  AccessControlUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;

  /// @notice Role for accepting slash recipient updates
  bytes32 public constant SLASH_RECIPIENT_ROLE = keccak256('SLASH_RECIPIENT_ROLE');

  /// @notice Role for authorized contract upgrades
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');

  /// @notice Reference to the vending machine
  IVendingMachine public vendingMachine;

  /// @notice Reference to the VMT token for voting
  VoteToken public voteToken;

  /// @notice Minimum deposit required to register as a stocker
  uint256 public minDeposit;

  /// @notice Duration of voting period in seconds
  uint256 public votingPeriod;

  /// @notice Lock period after deregistration before withdrawal is allowed
  uint256 public withdrawalLockPeriod;

  /// @notice Address that receives slashed deposits
  address public slashRecipient;

  /// @notice Counter for proposal IDs
  uint256 private _proposalCounter;

  /// @notice Mapping of stocker address to their info
  mapping(address => StockerInfo) private _stockers;

  /// @notice Mapping of stocker address to their deregistration timestamp (0 if not deregistered)
  mapping(address => uint256) private _deregistrationTime;

  /// @notice Mapping of proposal ID to proposal info
  mapping(uint256 => SlashProposal) private _proposals;

  /// @notice Mapping of proposal ID to voter address to whether they voted
  mapping(uint256 => mapping(address => bool)) private _hasVoted;

  /// @notice Mapping of stocker address to their pending proposal IDs
  mapping(address => uint256[]) private _pendingProposals;

  /// @notice Reserved storage gap for future upgrades
  uint256[50] private __gap;

  /// @notice Disable initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initialize the slashing extension contract
   * @param _vendingMachine Address of the vending machine contract
   * @param _voteToken Address of the VMT token
   * @param _minDeposit Minimum deposit required to register as a stocker
   * @param _votingPeriod Duration of voting period in seconds
   * @param _withdrawalLockPeriod Lock period after deregistration
   * @param _slashRecipient Address that receives slashed deposits
   */
  function initialize(
    address _vendingMachine,
    address _voteToken,
    uint256 _minDeposit,
    uint256 _votingPeriod,
    uint256 _withdrawalLockPeriod,
    address _slashRecipient
  ) public initializer {
    if (_vendingMachine == address(0)) revert ZeroAddress();
    if (_voteToken == address(0)) revert ZeroAddress();
    if (_slashRecipient == address(0)) revert ZeroAddress();

    __AccessControl_init();

    vendingMachine = IVendingMachine(_vendingMachine);
    voteToken = VoteToken(_voteToken);
    minDeposit = _minDeposit;
    votingPeriod = _votingPeriod;
    withdrawalLockPeriod = _withdrawalLockPeriod;
    slashRecipient = _slashRecipient;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(SLASH_RECIPIENT_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
  }

  /**
   * @notice Update the slash recipient address
   * @param newRecipient New recipient address
   */
  function setSlashRecipient(address newRecipient) external onlyRole(SLASH_RECIPIENT_ROLE) {
    if (newRecipient == address(0)) revert ZeroAddress();
    slashRecipient = newRecipient;
  }

  /// @inheritdoc ISlashingExtension
  function registerStocker(address depositToken, uint256 depositAmount) external nonReentrant {
    if (_stockers[msg.sender].isActive) revert StockerAlreadyRegistered();
    if (depositAmount < minDeposit) revert InsufficientDeposit();
    if (!vendingMachine.isTokenAccepted(depositToken)) revert DepositTokenNotAccepted();

    // Transfer deposit from stocker
    IERC20(depositToken).safeTransferFrom(msg.sender, address(this), depositAmount);

    // Register stocker
    _stockers[msg.sender] = StockerInfo({
      stocker: msg.sender,
      depositAmount: depositAmount,
      depositToken: depositToken,
      isActive: true,
      registeredAt: block.timestamp
    });

    // Clear any previous deregistration time
    _deregistrationTime[msg.sender] = 0;

    emit StockerRegistered(msg.sender, depositToken, depositAmount);
  }

  /// @inheritdoc ISlashingExtension
  function deregisterStocker() external {
    StockerInfo storage stocker = _stockers[msg.sender];
    if (!stocker.isActive) revert StockerNotRegistered();

    // Check for pending proposals
    uint256[] storage pending = _pendingProposals[msg.sender];
    for (uint256 i = 0; i < pending.length; i++) {
      SlashProposal storage proposal = _proposals[pending[i]];
      if (!proposal.executed) {
        revert HasPendingProposals();
      }
    }

    stocker.isActive = false;
    _deregistrationTime[msg.sender] = block.timestamp;

    emit StockerDeregistered(msg.sender);
  }

  /// @inheritdoc ISlashingExtension
  function withdrawDeposit() external nonReentrant {
    StockerInfo storage stocker = _stockers[msg.sender];
    if (stocker.depositAmount == 0) revert StockerNotRegistered();
    if (stocker.isActive) revert StockerNotActive();

    uint256 deregTime = _deregistrationTime[msg.sender];
    if (deregTime == 0 || block.timestamp < deregTime + withdrawalLockPeriod) {
      revert WithdrawalLocked();
    }

    uint256 amount = stocker.depositAmount;
    address token = stocker.depositToken;

    // Clear deposit
    stocker.depositAmount = 0;
    stocker.depositToken = address(0);

    // Transfer deposit back to stocker
    IERC20(token).safeTransfer(msg.sender, amount);

    emit DepositWithdrawn(msg.sender, token, amount);
  }

  /// @inheritdoc ISlashingExtension
  function proposeSlash(address stocker, string calldata reason) external returns (uint256 proposalId) {
    StockerInfo storage stockerInfo = _stockers[stocker];
    if (!stockerInfo.isActive && stockerInfo.depositAmount == 0) revert StockerNotRegistered();

    // Proposer must have voting power
    uint256 proposerVotes = voteToken.getVotes(msg.sender);
    if (proposerVotes == 0) revert NoVotingPower();

    proposalId = ++_proposalCounter;
    uint256 deadline = block.timestamp + votingPeriod;

    _proposals[proposalId] = SlashProposal({
      id: proposalId,
      stocker: stocker,
      reason: reason,
      proposer: msg.sender,
      votesFor: 0,
      votesAgainst: 0,
      snapshotBlock: block.number,
      deadline: deadline,
      executed: false,
      slashed: false
    });

    _pendingProposals[stocker].push(proposalId);

    emit SlashProposalCreated(proposalId, stocker, msg.sender, reason, deadline);
  }

  /// @inheritdoc ISlashingExtension
  function castVote(uint256 proposalId, bool support) external {
    SlashProposal storage proposal = _proposals[proposalId];
    if (proposal.id == 0) revert ProposalNotFound();
    if (block.timestamp > proposal.deadline) revert VotingEnded();
    if (proposal.executed) revert ProposalAlreadyExecuted();
    if (_hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

    // Get voting power at snapshot block
    uint256 votes = voteToken.getPastVotes(msg.sender, proposal.snapshotBlock);
    if (votes == 0) revert NoVotingPower();

    _hasVoted[proposalId][msg.sender] = true;

    if (support) {
      proposal.votesFor += votes;
    } else {
      proposal.votesAgainst += votes;
    }

    emit VoteCast(proposalId, msg.sender, support, votes);
  }

  /// @inheritdoc ISlashingExtension
  function executeProposal(uint256 proposalId) external nonReentrant {
    SlashProposal storage proposal = _proposals[proposalId];
    if (proposal.id == 0) revert ProposalNotFound();
    if (block.timestamp <= proposal.deadline) revert VotingNotEnded();
    if (proposal.executed) revert ProposalAlreadyExecuted();

    proposal.executed = true;

    // Majority vote determines outcome
    bool shouldSlash = proposal.votesFor > proposal.votesAgainst;
    proposal.slashed = shouldSlash;

    if (shouldSlash) {
      _executeSlash(proposal.stocker);
    }

    // Remove from pending proposals
    _removePendingProposal(proposal.stocker, proposalId);

    emit ProposalExecuted(proposalId, shouldSlash, proposal.votesFor, proposal.votesAgainst);
  }

  /// @inheritdoc ISlashingExtension
  function getStockerInfo(address stocker) external view returns (StockerInfo memory) {
    return _stockers[stocker];
  }

  /// @inheritdoc ISlashingExtension
  function getProposal(uint256 proposalId) external view returns (SlashProposal memory) {
    return _proposals[proposalId];
  }

  /// @inheritdoc ISlashingExtension
  function isActiveStocker(address stocker) external view returns (bool) {
    return _stockers[stocker].isActive;
  }

  /// @inheritdoc ISlashingExtension
  function getPendingProposals(address stocker) external view returns (uint256[] memory) {
    uint256[] storage allProposals = _pendingProposals[stocker];
    uint256 pendingCount = 0;

    // Count pending (non-executed) proposals
    for (uint256 i = 0; i < allProposals.length; i++) {
      if (!_proposals[allProposals[i]].executed) {
        pendingCount++;
      }
    }

    // Build result array
    uint256[] memory result = new uint256[](pendingCount);
    uint256 index = 0;
    for (uint256 i = 0; i < allProposals.length; i++) {
      if (!_proposals[allProposals[i]].executed) {
        result[index++] = allProposals[i];
      }
    }

    return result;
  }

  /// @inheritdoc ISlashingExtension
  function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
    return _hasVoted[proposalId][voter];
  }

  /**
   * @notice Get the deregistration timestamp for a stocker
   * @param stocker Address of the stocker
   * @return Timestamp of deregistration (0 if not deregistered)
   */
  function getDeregistrationTime(address stocker) external view returns (uint256) {
    return _deregistrationTime[stocker];
  }

  /**
   * @notice Get the current proposal counter
   * @return Current proposal ID counter
   */
  function proposalCount() external view returns (uint256) {
    return _proposalCounter;
  }

  /**
   * @notice Execute the slash by transferring deposit to slash recipient
   * @param stocker Address of the stocker being slashed
   */
  function _executeSlash(address stocker) private {
    StockerInfo storage stockerInfo = _stockers[stocker];

    uint256 amount = stockerInfo.depositAmount;
    address token = stockerInfo.depositToken;

    if (amount == 0) return;

    // Clear deposit and deactivate
    stockerInfo.depositAmount = 0;
    stockerInfo.depositToken = address(0);
    stockerInfo.isActive = false;

    // Transfer slashed funds to recipient
    IERC20(token).safeTransfer(slashRecipient, amount);

    emit StockerSlashed(stocker, token, amount, slashRecipient);
  }

  /**
   * @notice Remove a proposal from the pending proposals list
   * @param stocker Address of the stocker
   * @param proposalId ID of the proposal to remove
   */
  function _removePendingProposal(address stocker, uint256 proposalId) private {
    uint256[] storage pending = _pendingProposals[stocker];
    for (uint256 i = 0; i < pending.length; i++) {
      if (pending[i] == proposalId) {
        pending[i] = pending[pending.length - 1];
        pending.pop();
        break;
      }
    }
  }

  /**
   * @notice Required by UUPS pattern to authorize upgrades
   * @param newImplementation Address of the new implementation
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
