// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "interfaces/iface.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title Reward Pool
 */
contract RewardPool is Initializable, PausableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using Address for address;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private constant MULTIPLIER = 1e18; 

    struct UserInfo {
        uint256 accSharePoint; // acc share point for last user balance change
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardBalance;  // pending distribution
    }
    
    uint256 private totalStaked;    // total staked ethers
    uint256 private accShare;   // current earnings per share
    mapping(address => UserInfo) public userInfo; // claimaddr -> info

    uint256 accountedBalance;   // for tracking of overall deposits

    
    /** 
     * ======================================================================================
     * 
     * SYSTEM SETTINGS, OPERATED VIA OWNER(DAO/TIMELOCK)
     * 
     * ======================================================================================
     */
    receive() external payable { }

    /**
     * @dev pause the contract
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev unpause the contract
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev initialization address
     */
    function initialize() initializer public {
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /** 
     * ======================================================================================
     * 
     * USER FUNCTIONS
     * 
     * ======================================================================================
     */
    // to join the reward pool
    function joinpool(address claimaddr, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        updateReward();

        UserInfo storage info = userInfo[claimaddr];

        // settle current pending distribution
        info.rewardBalance += (accShare - info.accSharePoint) * info.amount / MULTIPLIER;
        info.amount += amount;
        info.accSharePoint = accShare;

        // update total staked
        totalStaked += amount;
    }

    // claimRewards
    function claimRewards(address beneficiary, uint256 amountRequired) external nonReentrant {
        updateReward();

        UserInfo storage info = userInfo[msg.sender];

        // settle current pending distribution
        info.rewardBalance += (accShare - info.accSharePoint) * info.amount / MULTIPLIER;
        info.accSharePoint = accShare;

        // check
        require(info.rewardBalance >= amountRequired, "INSUFFICIENT_REWARD");

        // account & transfer
        _balanceDecrease(amountRequired);
        payable(beneficiary).sendValue(amountRequired);
    }

    /**
     * @dev updateReward of tx fee
     */
    function updateReward() public {
        require(address(this).balance >= accountedBalance);
        uint256 newReward = address(this).balance - accountedBalance;
        if (newReward > 0) {
            accShare += newReward * MULTIPLIER / totalStaked;
            accountedBalance = address(this).balance;
        }
    }

    /**
     * ======================================================================================
     * 
     * VIEW FUNCTIONS
     * 
     * ======================================================================================
     */
     function getPendingReward(address claimaddr) external view returns (uint256) {
        require(address(this).balance >= accountedBalance);
        uint256 newReward = address(this).balance - accountedBalance;
        UserInfo storage info = userInfo[claimaddr];

        return info.rewardBalance + (accShare + newReward * MULTIPLIER / totalStaked - info.accSharePoint)  * info.amount / MULTIPLIER;
     }

    /** 
     * ======================================================================================
     * 
     * INTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */

    function _balanceIncrease(uint256 amount) internal { accountedBalance += amount; }
    function _balanceDecrease(uint256 amount) internal { accountedBalance -= amount; }

}
