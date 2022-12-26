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
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardBalance;  // pending distribution
        uint256 rewardDebt; // reward debts
    }
    
    uint256 private totaStaked;
    uint256 private accShare;
    mapping(address => UserInfo) public userInfo;

    uint256 lastBalance;
    
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
        syncBalance();

        UserInfo storage info = userInfo[claimaddr];

        // settle current pending distribution
        info.rewardBalance += accShare * info.amount / MULTIPLIER - info.rewardDebt;

        // update amount & rewardDebt
        info.amount += amount;
        info.rewardDebt = accShare * info.amount / MULTIPLIER;

        // update total staked
        totaStaked += amount;
    }

    // claimRewards
    function claimRewards(address beneficiary, uint256 amountRequired) external {
        syncBalance();

        UserInfo storage info = userInfo[msg.sender];

        // settle current pending distribution
        info.rewardBalance += accShare * info.amount / MULTIPLIER - info.rewardDebt;
        info.rewardDebt = accShare * info.amount / MULTIPLIER;

        // check
        require(info.rewardBalance >= amountRequired, "INSUFFICIENT_REWARD");

        // transfer
        payable(beneficiary).sendValue(amountRequired);
    }

    /**
     * @dev balance sync of tx fee
     */
    function syncBalance() public {
        require(address(this).balance >= lastBalance);
        uint256 newReward = address(this).balance - lastBalance;
        if (newReward > 0) {
            accShare += newReward * MULTIPLIER / totaStaked;
            lastBalance = address(this).balance;
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
        require(address(this).balance >= lastBalance);
        uint256 newReward = address(this).balance - lastBalance;
        UserInfo storage info = userInfo[claimaddr];

        return info.rewardBalance + (accShare + newReward * MULTIPLIER / totaStaked) * info.amount / MULTIPLIER - info.rewardDebt;
     }
}