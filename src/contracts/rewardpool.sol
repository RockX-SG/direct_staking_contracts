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

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    uint256 private constant MULTIPLIER = 1e18; 

    struct UserInfo {
        uint256 accSharePoint; // acc share point for last user balance change
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardBalance;  // pending distribution
    }
    
    uint256 public managerFeeShare; // manager's fee in 1/1000
    uint256 public managerRevenue; // accounted manager's revenue

    uint256 private totalStaked;    // total staked ethers
    uint256 private accShare;   // current earnings per share
    mapping(address => UserInfo) public userInfo; // claimaddr -> info

    uint256 accountedBalance;   // for tracking of overall deposits

    /**
     * @dev empty reserved space for future adding of variables
     */
    uint256[32] private __gap;

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

        // init default values
        managerFeeShare = 200;  // 20%

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /** 
     * ======================================================================================
     * 
     * MANAGER FUNCTIONS
     * 
     * ======================================================================================
     */
    /**
     * @dev manager withdraw revenue
     */
    function withdrawManagerRevenue(uint256 amount, address to) external nonReentrant onlyRole(MANAGER_ROLE)  {
        require(amount <= managerRevenue, "WITHDRAW_EXCEEDED_MANAGER_REVENUE");

        // track balance change
        _balanceDecrease(amount);
        managerRevenue -= amount;

        payable(to).sendValue(amount);

        emit ManagerFeeWithdrawed(amount, to);
    }

    /**
     * @dev set manager's fee in 1/1000
     */
    function setManagerFeeShare(uint256 milli) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(milli >=0 && milli <=1000, "SHARE_OUT_OF_RANGE");
        managerFeeShare = milli;

        emit ManagerFeeSet(milli);
    }

    /** 
     * ======================================================================================
     * 
     * USER FUNCTIONS
     * 
     * ======================================================================================
     */
    // to join the reward pool
    function joinpool(address claimaddr, uint256 amount) external onlyRole(CONTROLLER_ROLE) whenNotPaused {
        updateReward();

        UserInfo storage info = userInfo[claimaddr];

        // settle current pending distribution
        info.rewardBalance += (accShare - info.accSharePoint) * info.amount / MULTIPLIER;
        info.amount += amount;
        info.accSharePoint = accShare;

        // update total staked
        totalStaked += amount;

        // log
        emit PoolJoined(claimaddr, amount);
    }

    // to leave a pool
    function leavepool(address claimaddr, uint256 amount) external onlyRole(CONTROLLER_ROLE) whenNotPaused {
        updateReward();

        UserInfo storage info = userInfo[claimaddr];

        // settle current pending distribution
        info.rewardBalance += (accShare - info.accSharePoint) * info.amount / MULTIPLIER;
        info.amount -= amount;
        info.accSharePoint = accShare;

        // update total staked
        totalStaked -= amount;

        // log
        emit PoolLeft(claimaddr, amount);
    }

    // claimRewards
    function claimRewards(address beneficiary, uint256 amount) external nonReentrant whenNotPaused {
        updateReward();

        UserInfo storage info = userInfo[msg.sender];

        // settle current pending distribution
        info.rewardBalance += (accShare - info.accSharePoint) * info.amount / MULTIPLIER;
        info.accSharePoint = accShare;

        // check
        require(info.rewardBalance >= amount, "INSUFFICIENT_REWARD");

        // account & transfer
        _balanceDecrease(amount);
        payable(beneficiary).sendValue(amount);

        // log
        emit Claimed(beneficiary, amount);
    }

    /**
     * @dev updateReward of tx fee
     */
    function updateReward() public {
        if (address(this).balance > accountedBalance) {
            uint256 reward = address(this).balance - accountedBalance;

            // distribute to manager and pool
            uint256 managerReward = reward * managerFeeShare / 1000;
            uint256 poolReward = reward - managerReward;

            accShare += poolReward * MULTIPLIER / totalStaked;
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
        uint256 newReward;
        if (address(this).balance > accountedBalance) {
            newReward = address(this).balance - accountedBalance;
        }

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
    function _balanceDecrease(uint256 amount) internal { accountedBalance -= amount; }

    /**
     * ======================================================================================
     * 
     * SYSTEM EVENTS
     *
     * ======================================================================================
     */
    event PoolJoined(address claimaddr, uint256 amount);
    event PoolLeft(address claimaddr, uint256 amount);
    event Claimed(address beneficiary, uint256 amount);
    event ManagerFeeWithdrawed(uint256 amount, address to);
    event ManagerFeeSet(uint256 milli);
}
