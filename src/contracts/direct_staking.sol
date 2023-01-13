// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "interfaces/iface.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
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

    // structure to record taking info.
    struct ValidatorInfo {
        bytes pubkey;
        address withdrawalAddress;
        address claimAddress;
        uint256 extraData; // a 256bit extra data, could be used in DID to ref a user

        // mark exiting
        bool exiting;
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
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant DEPOSIT_SIZE = 32 ether;

    uint256 private constant MULTIPLIER = 1e18; 
    uint256 private constant DEPOSIT_AMOUNT_UNIT = 1000000000 wei;
    uint256 private constant SIGNATURE_LENGTH = 96;
    uint256 private constant PUBKEY_LENGTH = 48;
    
    address public ethDepositContract;  // ETH 2.0 Deposit contract
    address public rewardPool; // reward pool address
    address public sysSigner; // signer

    // pubkeys pushed by owner
    // [0, 1,2,3,{4,5,6,7}, 8,9, 10], which:
    //  0-3: deposited to official contract,
    //  4-7: user deposited, awaiting to be signed and then to be deposit to official contract,
    //  8-10: registered unused pubkeys 
    ValidatorInfo [] private validatorRegistry;

    // user apply for validator exit
    uint256 [] private exitQueue;
   
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
        _grantRole(REGISTRY_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @dev set reward pool contract address
     */
    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sysSigner = _signer;

        emit SignerSet(_signer);
    }

    /**
     * @dev set reward pool contract address
     */
    function setRewardPool(address _rewardPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardPool = _rewardPool;

        emit RewardPoolContractSet(_rewardPool);
    }

    /**
     * @dev set eth deposit contract address
     */
    function setETHDepositContract(address _ethDepositContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ethDepositContract = _ethDepositContract;

        emit DepositContractSet(_ethDepositContract);
    }

    /**
     * ======================================================================================
     * 
     * VIEW FUNCTIONS
     * 
     * ======================================================================================
     */

    /**
     * @dev return registered validator by index
     */
    function getValidatorInfo(uint256 idx) external view returns (
        bytes memory pubkey,
        address withdrawalAddress,
        address claimAddress,
        uint256 extraData
     ){
        ValidatorInfo storage info = validatorRegistry[idx];  
        return (info.pubkey, info.withdrawalAddress, info.claimAddress, info.extraData);
    }

    /**
     * @dev return registered validator by range
     */
    function getValidatorInfos(uint256 from, uint256 to) external view returns (
        bytes [] memory pubkeys,
        address [] memory withdrawalAddresses,
        address [] memory claimAddresses,
        uint256 [] memory extraDatas
     ){
        pubkeys = new bytes[](to - from);
        withdrawalAddresses = new address[](to - from);
        claimAddresses =  new address[](to - from);
        extraDatas = new uint256[](to - from);

        uint256 counter = 0;
        for (uint i = from; i < to;i++) {
            ValidatorInfo storage info = validatorRegistry[i];
            pubkeys[counter] = info.pubkey;
            withdrawalAddresses[counter] = info.withdrawalAddress;
            claimAddresses[counter] = info.claimAddress;
            extraDatas[counter] = info.extraData;

            counter++;
        }
    }

    /**
     * @dev return next validator ID to register pubkey
     */
    function getNextValidators() external view returns (uint256) { return validatorRegistry.length; }

    /**
     * @dev return exit queue
     */
    function getExitQueue(uint256 from, uint256 to) external view returns (uint256[] memory) { 
        uint256[] memory ids = new uint256[](to - from);
        uint256 counter = 0;
        for (uint i = from; i < to;i++) {
            ids[counter] = exitQueue[i];
            counter++;
        }
        return ids;
    }

    /**
     * @dev return exit queue length
     */
    function getExitQueueLength() external view returns (uint256) { return exitQueue.length; }

    /**
     * ======================================================================================
     * 
     * USER EXTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */
     
    /**
     * @dev user stakes
     */
    function stake(
        address claimaddr,
        address withdrawaddr,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes calldata paramsSig, uint256 extradata, uint256 fee) external payable whenNotPaused {

        // global check
        _require(signatures.length <= 10, "RISKY_DEPOSITS");
        _require(signatures.length == pubkeys.length, "INCORRECT_SUBMITS");
        _require(sysSigner != address(0x0), "SYS_SIGNER_NOT_SET");
        _require(ethDepositContract != address(0x0), "ETH_DEPOSIT_NOT_SET");
        _require(rewardPool != address(0x0), "REWARDPOOL_NOT_SET");

        // rockx signature verification
        bytes32 digest = ECDSA.toEthSignedMessageHash(_digest(claimaddr, withdrawaddr, pubkeys, signatures));
        address signer = ECDSA.recover(digest, paramsSig);
        _require(signer == sysSigner, Strings.toHexString(signer));

        // validity check
        _require(withdrawaddr != address(0x0), "ZERO_ADDRESS");
        _require(claimaddr != address(0x0), "ZERO_ADDRESS");

        uint256 ethersToStake = msg.value - fee;
        _require(ethersToStake % DEPOSIT_SIZE == 0, "ROUND_TO_32ETHERS");
        uint256 nodesAmount = ethersToStake / DEPOSIT_SIZE;
        _require(signatures.length == nodesAmount, "MISMATCHED_ETHERS");

        // deposit
        for (uint256 i = 0;i < nodesAmount;i++) {
            ValidatorInfo memory info;
            info.pubkey = pubkeys[i];
            info.withdrawalAddress = withdrawaddr;
            info.claimAddress = claimaddr;
            info.extraData = extradata;
            validatorRegistry.push(info);

            // deposit to offical
            _deposit(pubkeys[i], signatures[i], info.withdrawalAddress);

            // join the reward pool once it's deposited to official
            IRewardPool(rewardPool).joinpool(info.claimAddress, DEPOSIT_SIZE);
        }

        // log
        emit Staked(msg.sender, msg.value);
    }

    /**
     * @dev user exits his validator
     */
    function exit(uint256 validatorId) external {
        ValidatorInfo storage info = validatorRegistry[validatorId];
        require(!info.exiting, "EXITING");
        require(msg.sender == info.claimAddress, "CLAIM_ADDR_MISMATCH");

        info.exiting = true;
        exitQueue.push(validatorId);

        // to leave the reward pool
        IRewardPool(rewardPool).leavepool(info.claimAddress, DEPOSIT_SIZE);
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
    function _deposit(bytes memory pubkey, bytes memory signature, address withdrawal_address) internal {
        uint256 value = DEPOSIT_SIZE;
        uint256 depositAmount = DEPOSIT_SIZE / DEPOSIT_AMOUNT_UNIT;
        assert(depositAmount * DEPOSIT_AMOUNT_UNIT == value);    // properly rounded

        // initiate withdrawal credential 
        // uint8('0x1') + 11 bytes(0) + this.address
        bytes memory cred = abi.encodePacked(bytes1(0x01), new bytes(11), withdrawal_address);
        bytes32 withdrawal_credential = BytesLib.toBytes32(cred, 0);

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

    // cheaper version of require
    function _require(bool condition, string memory text) private pure {
        require (condition, text);
    }

    // digest params
    function _digest(address claimaddr,
        address withdrawaddr,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures) private pure returns (bytes32) {

        bytes32 digest = sha256(abi.encode(claimaddr, withdrawaddr));

        for (uint i=0;i<pubkeys.length;i++) {
            digest = sha256(abi.encode(digest, pubkeys[i], signatures[i]));
        }

        return digest;
    }
    
    /**
     * ======================================================================================
     * 
     * SYSTEM EVENTS
     *
     * ======================================================================================
     */
    event RewardPoolContractSet(address addr);
    event DepositContractSet(address addr);
    event SignerSet(address addr);
    event Staked(address addr, uint256 amount);
}