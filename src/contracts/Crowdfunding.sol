// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
import {VoteToken} from './VoteToken.sol';

/**
 * @title Crowdfunding
 * @notice A crowdfunding platform for Mutual Vend expansion
 * @dev Contributors receive VoteTokens proportional to their contribution
 */
contract Crowdfunding is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    bytes32 public constant CAMPAIGN_MANAGER_ROLE = keccak256('CAMPAIGN_MANAGER_ROLE');
    
    VoteToken public immutable voteToken;
    
    struct Campaign {
        uint256 campaignId;
        string title;
        string description;
        string imageURI;
        address creator;
        uint256 goal;
        uint256 deadline;
        uint256 raised;
        bool isActive;
        bool goalReached;
        bool fundsWithdrawn;
        IERC20[] acceptedTokens;
        mapping(address => uint256) contributions; // token => amount
        mapping(address => uint256) userContributions; // user => total value
        address[] contributors;
    }
    
    uint256 public campaignCounter;
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => bool)) public hasContributed; // campaignId => user => bool
    
    uint256 public constant MIN_CAMPAIGN_DURATION = 1 days;
    uint256 public constant MAX_CAMPAIGN_DURATION = 90 days;
    uint256 public constant VOTE_TOKEN_MULTIPLIER = 10; // 1 USD = 10 VoteTokens
    
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 goal,
        uint256 deadline
    );
    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        address token,
        uint256 amount,
        uint256 voteTokensEarned
    );
    event CampaignGoalReached(uint256 indexed campaignId, uint256 raised);
    event FundsWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);
    event RefundProcessed(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    
    error InvalidDuration();
    error InvalidGoal();
    error CampaignNotActive();
    error CampaignEnded();
    error GoalNotReached();
    error FundsAlreadyWithdrawn();
    error NothingToRefund();
    error InvalidToken();
    
    constructor(address _voteToken) {
        voteToken = VoteToken(_voteToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAMPAIGN_MANAGER_ROLE, msg.sender);
    }
    
    function createCampaign(
        string calldata _title,
        string calldata _description,
        string calldata _imageURI,
        uint256 _goal,
        uint256 _duration,
        address[] calldata _acceptedTokens
    ) external returns (uint256) {
        if (_goal == 0) revert InvalidGoal();
        if (_duration < MIN_CAMPAIGN_DURATION || _duration > MAX_CAMPAIGN_DURATION) {
            revert InvalidDuration();
        }
        
        campaignCounter++;
        
        Campaign storage campaign = campaigns[campaignCounter];
        campaign.campaignId = campaignCounter;
        campaign.title = _title;
        campaign.description = _description;
        campaign.imageURI = _imageURI;
        campaign.creator = msg.sender;
        campaign.goal = _goal;
        campaign.deadline = block.timestamp + _duration;
        campaign.isActive = true;
        
        // Set accepted tokens
        for (uint256 i = 0; i < _acceptedTokens.length; i++) {
            campaign.acceptedTokens.push(IERC20(_acceptedTokens[i]));
        }
        
        emit CampaignCreated(campaignCounter, msg.sender, _title, _goal, campaign.deadline);
        return campaignCounter;
    }
    
    function contribute(
        uint256 _campaignId,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        _validateContribution(_campaignId, _token, _amount);
        
        Campaign storage campaign = campaigns[_campaignId];
        
        // Transfer tokens from contributor
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        
        // Add to contributor list if first contribution
        if (!hasContributed[_campaignId][msg.sender]) {
            campaign.contributors.push(msg.sender);
            hasContributed[_campaignId][msg.sender] = true;
        }
        
        // Update contribution tracking
        campaign.contributions[_token] += _amount;
        campaign.userContributions[msg.sender] += _amount;
        campaign.raised += _amount;
        
        // Mint VoteTokens to contributor
        uint256 voteTokensToMint = _amount * VOTE_TOKEN_MULTIPLIER;
        voteToken.mint(msg.sender, voteTokensToMint);
        
        // Check if goal reached
        if (!campaign.goalReached && campaign.raised >= campaign.goal) {
            campaign.goalReached = true;
            emit CampaignGoalReached(_campaignId, campaign.raised);
        }
        
        emit ContributionMade(_campaignId, msg.sender, _token, _amount, voteTokensToMint);
    }
    
    function _validateContribution(
        uint256 _campaignId,
        address _token,
        uint256 _amount
    ) internal view {
        Campaign storage campaign = campaigns[_campaignId];
        if (!campaign.isActive) revert CampaignNotActive();
        if (block.timestamp >= campaign.deadline) revert CampaignEnded();
        if (_amount == 0) revert InvalidGoal();
        
        // Check if token is accepted
        bool tokenAccepted = false;
        for (uint256 i = 0; i < campaign.acceptedTokens.length; i++) {
            if (address(campaign.acceptedTokens[i]) == _token) {
                tokenAccepted = true;
                break;
            }
        }
        if (!tokenAccepted) revert InvalidToken();
    }
    
    function withdrawFunds(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        if (msg.sender != campaign.creator) revert();
        if (!campaign.goalReached) revert GoalNotReached();
        if (campaign.fundsWithdrawn) revert FundsAlreadyWithdrawn();
        
        campaign.fundsWithdrawn = true;
        campaign.isActive = false;
        
        // Transfer all tokens to creator
        for (uint256 i = 0; i < campaign.acceptedTokens.length; i++) {
            IERC20 token = campaign.acceptedTokens[i];
            uint256 amount = campaign.contributions[address(token)];
            if (amount > 0) {
                token.safeTransfer(campaign.creator, amount);
            }
        }
        
        emit FundsWithdrawn(_campaignId, campaign.creator, campaign.raised);
    }
    
    function claimRefund(uint256 _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.goalReached) revert();
        if (block.timestamp < campaign.deadline) revert();
        if (campaign.userContributions[msg.sender] == 0) revert NothingToRefund();
        
        uint256 userContribution = campaign.userContributions[msg.sender];
        campaign.userContributions[msg.sender] = 0;
        
        // Calculate proportional refund for each token
        for (uint256 i = 0; i < campaign.acceptedTokens.length; i++) {
            IERC20 token = campaign.acceptedTokens[i];
            uint256 tokenTotal = campaign.contributions[address(token)];
            if (tokenTotal > 0) {
                uint256 refundAmount = (tokenTotal * userContribution) / campaign.raised;
                if (refundAmount > 0) {
                    token.safeTransfer(msg.sender, refundAmount);
                }
            }
        }
        
        emit RefundProcessed(_campaignId, msg.sender, userContribution);
    }
    
    function getCampaign(uint256 _campaignId) external view returns (
        uint256 campaignId,
        string memory title,
        string memory description,
        string memory imageURI,
        address creator,
        uint256 goal,
        uint256 deadline,
        uint256 raised,
        bool isActive,
        bool goalReached,
        bool fundsWithdrawn
    ) {
        Campaign storage campaign = campaigns[_campaignId];
        return (
            campaign.campaignId,
            campaign.title,
            campaign.description,
            campaign.imageURI,
            campaign.creator,
            campaign.goal,
            campaign.deadline,
            campaign.raised,
            campaign.isActive,
            campaign.goalReached,
            campaign.fundsWithdrawn
        );
    }
    
    function getContributors(uint256 _campaignId) external view returns (address[] memory) {
        return campaigns[_campaignId].contributors;
    }
    
    function getUserContribution(
        uint256 _campaignId,
        address _user
    ) external view returns (uint256) {
        return campaigns[_campaignId].userContributions[_user];
    }
    
    function getAcceptedTokens(uint256 _campaignId) external view returns (address[] memory) {
        Campaign storage campaign = campaigns[_campaignId];
        address[] memory tokens = new address[](campaign.acceptedTokens.length);
        for (uint256 i = 0; i < campaign.acceptedTokens.length; i++) {
            tokens[i] = address(campaign.acceptedTokens[i]);
        }
        return tokens;
    }
}