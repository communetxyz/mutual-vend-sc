// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';

/**
 * @title ZKVerification
 * @notice A simple ZK-based age/identity verification using commit-reveal
 * @dev Uses commit-reveal scheme to verify age without revealing actual age
 */
contract ZKVerification is AccessControl {
    bytes32 public constant VERIFIER_ROLE = keccak256('VERIFIER_ROLE');
    
    struct Commitment {
        bytes32 commitment;
        uint256 timestamp;
        bool revealed;
        bool verified;
    }
    
    mapping(address => Commitment) public commitments;
    mapping(address => bool) public verified;
    mapping(bytes32 => bool) public usedProofs; // Prevent proof reuse
    
    uint256 public constant COMMIT_TIMEOUT = 1 hours;
    uint256 public constant MIN_AGE = 18;
    
    event CommitmentMade(address indexed user, bytes32 commitment);
    event VerificationRevealed(address indexed user, bool verified);
    event VerificationRevoked(address indexed user);
    
    error InvalidCommitment();
    error CommitmentExpired();
    error AlreadyVerified();
    error InvalidProof();
    error ProofAlreadyUsed();
    error NotCommitted();
    error TooEarly();
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
    }
    
    /**
     * @notice Commit to an age proof
     * @param _commitment keccak256(age, nonce, secret)
     */
    function commitAge(bytes32 _commitment) external {
        if (_commitment == bytes32(0)) revert InvalidCommitment();
        if (verified[msg.sender]) revert AlreadyVerified();
        
        commitments[msg.sender] = Commitment({
            commitment: _commitment,
            timestamp: block.timestamp,
            revealed: false,
            verified: false
        });
        
        emit CommitmentMade(msg.sender, _commitment);
    }
    
    /**
     * @notice Reveal age proof and get verified if age >= MIN_AGE
     * @param _age The actual age
     * @param _nonce Random nonce used in commitment
     * @param _secret Secret salt used in commitment
     */
    function revealAge(
        uint256 _age,
        uint256 _nonce,
        bytes32 _secret
    ) external {
        Commitment storage commitment = commitments[msg.sender];
        if (commitment.commitment == bytes32(0)) revert NotCommitted();
        if (commitment.revealed) revert AlreadyVerified();
        if (block.timestamp > commitment.timestamp + COMMIT_TIMEOUT) revert CommitmentExpired();
        
        // Verify commitment matches reveal
        bytes32 computedCommitment = keccak256(abi.encodePacked(_age, _nonce, _secret));
        if (computedCommitment != commitment.commitment) revert InvalidProof();
        if (usedProofs[computedCommitment]) revert ProofAlreadyUsed();
        
        // Mark as revealed
        commitment.revealed = true;
        usedProofs[computedCommitment] = true;
        
        // Verify age requirement
        bool ageVerified = _age >= MIN_AGE;
        commitment.verified = ageVerified;
        verified[msg.sender] = ageVerified;
        
        emit VerificationRevealed(msg.sender, ageVerified);
    }
    
    /**
     * @notice Batch verify users (for trusted verifiers)
     * @param _users Array of users to verify
     */
    function batchVerify(address[] calldata _users) external onlyRole(VERIFIER_ROLE) {
        for (uint256 i = 0; i < _users.length; i++) {
            if (!verified[_users[i]]) {
                verified[_users[i]] = true;
                emit VerificationRevealed(_users[i], true);
            }
        }
    }
    
    /**
     * @notice Revoke verification for a user
     * @param _user User to revoke verification for
     */
    function revokeVerification(address _user) external onlyRole(VERIFIER_ROLE) {
        if (verified[_user]) {
            verified[_user] = false;
            delete commitments[_user];
            emit VerificationRevoked(_user);
        }
    }
    
    /**
     * @notice Check if a user is verified
     * @param _user User to check
     * @return True if user is verified
     */
    function isVerified(address _user) external view returns (bool) {
        return verified[_user];
    }
    
    /**
     * @notice Get commitment details for a user
     * @param _user User to check
     * @return Commitment struct
     */
    function getCommitment(address _user) external view returns (Commitment memory) {
        return commitments[_user];
    }
    
    /**
     * @notice Check if commitment has expired
     * @param _user User to check
     * @return True if commitment has expired
     */
    function isCommitmentExpired(address _user) external view returns (bool) {
        Commitment memory commitment = commitments[_user];
        return commitment.timestamp > 0 && 
               block.timestamp > commitment.timestamp + COMMIT_TIMEOUT;
    }
    
    /**
     * @notice Generate commitment for testing purposes
     * @dev This should NOT be used in production - only for demo
     * @param _age Age to commit to
     * @param _nonce Random nonce
     * @param _secret Secret salt
     * @return Computed commitment hash
     */
    function generateCommitment(
        uint256 _age,
        uint256 _nonce,
        bytes32 _secret
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_age, _nonce, _secret));
    }
}