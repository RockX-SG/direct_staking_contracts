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
 * @title RockX Ethereum Direct Staking Contract
 */
contract DirectStaking is Initializable, PausableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using Address for address;
    
    // track ether debts to return to async caller
    struct Debt {
        address account;
        uint256 amount;
    }

    /**
        Incorrect storage preservation:

        |Implementation_v0   |Implementation_v1        |
        |--------------------|-------------------------|
        |address _owner      |address _lastContributor | <=== Storage collision!
        |mapping _balances   |address _owner           |
        |uint256 _supply     |mapping _balances        |
        |...                 |uint256 _supply          |
        |                    |...                      |
        Correct storage preservation:

        |Implementation_v0   |Implementation_v1        |
        |--------------------|-------------------------|
        |address _owner      |address _owner           |
        |mapping _balances   |mapping _balances        |
        |uint256 _supply     |uint256 _supply          |
        |...                 |address _lastContributor | <=== Storage extension.
        |                    |...                      |
    */

    // Always extend storage instead of modifying it
    // Variables in implementation v0 
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    uint256 private constant MULTIPLIER = 1e18; 
    uint256 private constant DEPOSIT_AMOUNT_UNIT = 1000000000 wei;
    uint256 private constant SIGNATURE_LENGTH = 96;
    uint256 private constant PUBKEY_LENGTH = 48;
    
    address public ethDepositContract;      // ETH 2.0 Deposit contract
    address public xETHAddress;             // xETH token address
    address public redeemContract;          // redeeming contract for user to pull ethers
    
    // pubkeys pushed by owner
    bytes [] private validatorRegistry;
    mapping(bytes32 => uint256) private pubkeyIndices; // indices of validatorRegistry by pubkey hash, starts from 1

    // credentials binded to validator Id when user stakes
    mapping(uint256 => bytes32) private bindedWithdrawalCredentials; // indices of validatorRegistry by pubkey hash, starts from 1


    // next validator id
    uint256 private nextValidatorId;
   
    /**
     * @dev empty reserved space for future adding of variables
     */
    uint256[31] private __gap;

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
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(REGISTRY_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev register a validator
     */
    function registerValidator(bytes calldata pubkey) external onlyRole(REGISTRY_ROLE) {
        require(pubkey.length == PUBKEY_LENGTH, "INCONSISTENT_PUBKEY_LEN");

        bytes32 pubkeyHash = keccak256(pubkey);
        require(pubkeyIndices[pubkeyHash] == 0, "DUPLICATED_PUBKEY");
        validatorRegistry.push(pubkey);
        pubkeyIndices[pubkeyHash] = validatorRegistry.length;
    }

    /**
     * @dev replace a validator in case of msitakes
     */
    function replaceValidator(bytes calldata oldpubkey, bytes calldata pubkey) external onlyRole(REGISTRY_ROLE) {
        require(pubkey.length == PUBKEY_LENGTH, "INCONSISTENT_PUBKEY_LEN");

        // mark old pub key to false
        bytes32 oldPubKeyHash = keccak256(oldpubkey);
        require(pubkeyIndices[oldPubKeyHash] > 0, "PUBKEY_NOT_EXSITS");
        uint256 index = pubkeyIndices[oldPubKeyHash] - 1;
        delete pubkeyIndices[oldPubKeyHash];

        // set new pubkey
        bytes32 pubkeyHash = keccak256(pubkey);
        validatorRegistry[index] = pubkey;
        pubkeyIndices[pubkeyHash] = index+1;
    }

    /**
     * @dev register a batch of validators
     */
    function registerValidators(bytes [] calldata pubkeys) external onlyRole(REGISTRY_ROLE) {        
        uint256 n = pubkeys.length;
        for(uint256 i=0;i<n;i++) {
            require(pubkeys[i].length == PUBKEY_LENGTH, "INCONSISTENT_PUBKEY_LEN");

            bytes32 pubkeyHash = keccak256(pubkeys[i]);
            require(pubkeyIndices[pubkeyHash] == 0, "DUPLICATED_PUBKEY");
            validatorRegistry.push(pubkeys[i]);
            pubkeyIndices[pubkeyHash] = validatorRegistry.length;
        }
    }
    
   
    /**
     * @dev batch deposit with offline signed signatures 
     */
    function batchDeposit(uint256 fromId, bytes [] calldata signatures) external onlyRole(REGISTRY_ROLE) {
        require(fromId == nextValidatorId, "MISMATCHED_VALIDATOR_ID");
        require(fromId + signatures.length <= validatorRegistry.length, "TOO_MANY_SIGNATURES");

        for (uint256 i = 0;i<signatures.length;i++) {
            require(signatures[i].length == SIGNATURE_LENGTH, "INCONSISTENT_SIG_LEN");
            _stake(validatorRegistry[fromId + i], signatures[i], bindedWithdrawalCredentials[fromId + i]);
            delete bindedWithdrawalCredentials[fromId + i];
            nextValidatorId++;
        }
    }


    /**
     * ======================================================================================
     * 
     * VIEW FUNCTIONS
     * 
     * ======================================================================================
     */

    /**
     * @dev return number of registered validator
     */
    function getRegisteredValidatorsCount() external view returns (uint256) {
        return validatorRegistry.length;
    }
    
    /**
     * @dev return a batch of validators credential
     */
    function getRegisteredValidators(uint256 idx_from, uint256 idx_to) external view returns (bytes [] memory pubkeys) {
        pubkeys = new bytes[](idx_to - idx_from);

        uint counter = 0;
        for (uint i = idx_from; i < idx_to;i++) {
            pubkeys[counter] = validatorRegistry[i];
            counter++;
        }
    }

    /**
     * @dev return next validator id
     */
    function getNextValidatorId() external view returns (uint256) { return nextValidatorId; }

    /**
     * ======================================================================================
     * 
     * EXTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */
    /**
     * @dev stake
     */
    function stake(uint256 deadline) external payable nonReentrant whenNotPaused {
        require(block.timestamp < deadline, "TRANSACTION_EXPIRED");
        require(msg.value > 0, "MINT_ZERO");
        require(msg.value % (32 ether) == 0, "ROUND_TO_32ETHERS");

        uint256 count = msg.value % 32 ether;
        for (uint256 i = 0;i < count;i++) {
            
        }
    }


    /** 
     * ======================================================================================
     * 
     * INTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */

    /**
     * @dev Invokes a deposit call to the official Deposit contract
     */
    function _stake(bytes memory pubkey, bytes memory signature, bytes32 withdrawal_credential) internal {
        uint256 value = DEPOSIT_SIZE;
        uint256 depositAmount = DEPOSIT_SIZE / DEPOSIT_AMOUNT_UNIT;
        assert(depositAmount * DEPOSIT_AMOUNT_UNIT == value);    // properly rounded

        // Compute deposit data root (`DepositData` hash tree root)
        // https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa#code
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(abi.encodePacked(
            sha256(BytesLib.slice(signature, 0, 64)),
            sha256(abi.encodePacked(BytesLib.slice(signature, 64, SIGNATURE_LENGTH - 64), bytes32(0)))
        ));
        
        bytes memory amount = to_little_endian_64(uint64(depositAmount));

        bytes32 depositDataRoot = sha256(abi.encodePacked(
            sha256(abi.encodePacked(pubkey_root, withdrawal_credential)),
            sha256(abi.encodePacked(amount, bytes24(0), signature_root))
        ));

        IDepositContract(ethDepositContract).deposit{value:DEPOSIT_SIZE} (
            pubkey, abi.encodePacked(withdrawal_credential), signature, depositDataRoot);
    }

    /**
     * @dev to little endian
     * https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa#code
     */
    function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    /**
     * ======================================================================================
     * 
     * ROCKX SYSTEM EVENTS
     *
     * ======================================================================================
     */
    event ValidatorActivated(uint256 nextValidatorId);
    event ValidatorStopped(uint256 stoppedCount, uint256 stoppedBalance);
    event RevenueAccounted(uint256 amount);
    event ValidatorSlashedStopped(uint256 stoppedCount, uint256 slashed);
    event ManagerAccountSet(address account);
    event ManagerFeeSet(uint256 milli);
    event ManagerFeeWithdrawed(uint256 amount, address);
    event WithdrawCredentialSet(bytes32 withdrawCredential);
    event DebtQueued(address creditor, uint256 amountEther);
    event XETHContractSet(address addr);
    event DepositContractSet(address addr);
    event RedeemContractSet(address addr);
    event BalanceSynced(uint256 diff);
}