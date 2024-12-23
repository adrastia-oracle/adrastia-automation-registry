// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IPriceOracle} from "@adrastia-oracle/adrastia-core/contracts/interfaces/IPriceOracle.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAutomationRegistryFactory} from "./IAutomationRegistryFactory.sol";
import {IAutomationRegistry} from "./IAutomationRegistry.sol";
import {IAutomationPoolMinimal} from "../pool/IAutomationPoolMinimal.sol";
import {StandardRoleManagement} from "../access/StandardRoleManagement.sol";
import {Roles} from "../access/Roles.sol";
import {AutomationPoolTypes} from "../pool/AutomationPoolTypes.sol";
import {IDiamondLoupe} from "../diamond/interfaces/IDiamondLoupe.sol";

// TODO:Billin terms: getBillingTerms(pool) to support pool-specific billing terms in the future
contract AutomationRegistry is IAutomationRegistry, Initializable, StandardRoleManagement {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /******************************************************************************************************************
     * CONSTANTS
     *****************************************************************************************************************/

    /**
     * @notice The token used to consult the gas price oracle.
     */
    address public constant GAS_PRICE_TOKEN = 0x0000000000000000000000000000000000000001;

    /******************************************************************************************************************
     * STORAGE
     *****************************************************************************************************************/

    /**
     * @notice The ID of the registry.
     */
    uint256 public override id;

    /**
     * @notice The address of the factory that created this registry.
     */
    address public override factory;

    /**
     * @notice The address of the registry diamond.
     */
    address public override diamond;

    /**
     * @notice The address of the pool beacon.
     */
    address public override poolBeacon;

    /**
     * @notice The address of the executor beacon.
     */
    address public override executorBeacon;

    /**
     * @notice The address of the pool diamond.
     */
    address public override poolDiamond;

    /**
     * @notice The list of pools created by this registry.
     */
    address[] internal _pools;

    /**
     * @notice The gas configuration of the registry.
     */
    GasConfig internal _gasConfig;

    /**
     * @notice The billing configuration of the registry.
     */
    BillingConfig internal _billingConfig;

    /**
     * @notice The worker configuration of the registry.
     */
    WorkerConfig internal _workerConfig;

    /**
     * @notice The metadata of the registry.
     */
    Metadata internal _metadata;

    /**
     * @notice The suggested batch for pools created by this registry, for UI purposes.
     * @dev A batchId of zero indicates that no batch is suggested. Invalid values are ignored. The first work
     * item is used as the suggested work item for all items; other work items are ignored.
     */
    AutomationPoolTypes.BatchMapping internal _suggestedBatch;

    /******************************************************************************************************************
     * INITIALIZER
     *****************************************************************************************************************/

    function initialize(
        uint256 registryId,
        address registryDiamond,
        address admin,
        address factory_,
        address poolBeacon_,
        address executorBeacon_,
        address poolDiamond_,
        Metadata calldata initialMetadata,
        GasConfig calldata initialGasConfig,
        BillingConfig calldata initialBillingConfig,
        WorkerConfig calldata initialWorkerConfig
    ) public virtual initializer {
        __AccessControlEnumerable_init();

        id = registryId;
        diamond = registryDiamond;
        factory = factory_;
        poolBeacon = poolBeacon_;
        executorBeacon = executorBeacon_;
        poolDiamond = poolDiamond_;

        _setMetadata(initialMetadata);
        _setGasConfig(initialGasConfig);
        _setBillingConfig(initialBillingConfig);
        _setWorkerConfig(initialWorkerConfig);

        _initializeRoles(admin);
    }

    function _initializeRoles(address admin) internal virtual {
        // PROTOCOL_ADMIN manages itself
        // Note: The factory manages the protocol admin role. This is required for front-end observability.
        _setRoleAdmin(Roles.PROTOCOL_ADMIN, Roles.PROTOCOL_ADMIN);

        // PROTOCOL_ADMIN manages REGISTRY_ADMIN
        _setRoleAdmin(Roles.REGISTRY_ADMIN, Roles.PROTOCOL_ADMIN);
        // REGISTRY_ADMIN manages REGISTRY_FINANCE_MANAGER
        _setRoleAdmin(Roles.REGISTRY_FINANCE_MANAGER, Roles.REGISTRY_ADMIN);
        // REGISTRY_ADMIN manages REGISTRY_MANAGER
        _setRoleAdmin(Roles.REGISTRY_MANAGER, Roles.REGISTRY_ADMIN);
        // REGISTRY_MANAGER manages REGISTRY_POOL_DEPLOYER
        _setRoleAdmin(Roles.REGISTRY_POOL_DEPLOYER, Roles.REGISTRY_MANAGER);

        /* Worker roles */

        // PROTOCOL_ADMIN manages WORKER_ADMIN
        _setRoleAdmin(Roles.WORKER_ADMIN, Roles.PROTOCOL_ADMIN);
        // WORKER_ADMIN manages WORKER_MANAGER
        _setRoleAdmin(Roles.WORKER_MANAGER, Roles.WORKER_ADMIN);
        // WORKER_MANAGER manages WORKER
        _setRoleAdmin(Roles.WORKER, Roles.WORKER_MANAGER);

        // Grant all management roles to the admin
        _grantRole(Roles.REGISTRY_ADMIN, admin);
        _grantRole(Roles.REGISTRY_FINANCE_MANAGER, admin);
        _grantRole(Roles.REGISTRY_MANAGER, admin);
        _grantRole(Roles.WORKER_ADMIN, admin);
        _grantRole(Roles.WORKER_MANAGER, admin);
        _grantRole(Roles.REGISTRY_POOL_DEPLOYER, admin);
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    receive() external payable {
        // Only pools can send ETH to the registry
        revert();
    }

    fallback() external payable {
        address facet = IDiamondLoupe(diamond).facetAddress(bytes4(msg.sig));
        if (facet == address(0)) {
            revert("AutomationRegistry: Function does not exist"); // TODO: Custom revert
        }

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the diamond.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function name() external view virtual override returns (string memory) {
        return _metadata.name;
    }

    function description() external view virtual override returns (string memory) {
        return _metadata.description;
    }

    function poolType() external view virtual override returns (uint16) {
        return _metadata.poolType;
    }

    function getPool(uint256 poolId) external view virtual override returns (address) {
        return _pools[poolId - 1];
    }

    function getPools() external view virtual override returns (address[] memory) {
        return _pools;
    }

    function getPoolsCount() external view virtual override returns (uint256) {
        return _pools.length;
    }

    function createPool() external virtual override {
        _authCreatePool();

        if (poolBeacon == address(0)) {
            revert MissingPoolBeacon();
        }

        // Collect pool creation fee
        (address billingToken, uint256 feePaid) = _collectPoolCreationFee();

        uint256 poolId = _pools.length + 1;

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,uint256,address,address)",
            address(this),
            poolId,
            msg.sender,
            poolDiamond
        );
        BeaconProxy proxy = new BeaconProxy(poolBeacon, hex"");
        _pools.push(address(proxy));

        (bool success, ) = address(proxy).call(data);
        if (!success) {
            revert FailedToInitializePool();
        }

        if (feePaid > 0) {
            address factory_ = factory;

            (uint16 protocolPoolCreationFee, , ) = IAutomationRegistryFactory(factory_).getFeeConfig();

            // Calculate protocol fee, rounding up
            uint256 protocolFee = (feePaid * protocolPoolCreationFee).ceilDiv(10000);
            uint256 feeToRegistry = feePaid - protocolFee;

            IERC20(billingToken).safeTransfer(factory_, protocolFee);

            emit PoolCreationFeeCollected(
                poolId,
                address(proxy),
                billingToken,
                protocolFee,
                feeToRegistry,
                block.timestamp
            );
        }

        emit PoolCreated(msg.sender, poolId, address(proxy), block.timestamp);
    }

    function setBillingConfig(BillingConfig calldata newConfig) external virtual {
        _authSetBillingConfig();

        _setBillingConfig(newConfig);
    }

    function setGasConfig(GasConfig calldata newConfig) external virtual {
        _authSetGasConfig();

        _setGasConfig(newConfig);
    }

    function setWorkerConfig(WorkerConfig calldata newConfig) external virtual {
        _authSetWorkerConfig();

        _setWorkerConfig(newConfig);
    }

    function setMetadata(Metadata calldata metadata) external virtual {
        _authSetMetadata();

        _setMetadata(metadata);
    }

    function setSuggestedBatch(AutomationPoolTypes.BatchMapping calldata batch) external virtual {
        _authSetSuggestedBatch();

        _suggestedBatch = batch;
    }

    function getGasConfig() external view virtual override returns (GasConfig memory) {
        return _gasConfig;
    }

    function getBillingConfig() external view virtual override returns (BillingConfig memory) {
        return _billingConfig;
    }

    function getWorkerConfig() external view virtual override returns (WorkerConfig memory) {
        return _workerConfig;
    }

    function getSuggestedBatch() external view virtual override returns (AutomationPoolTypes.BatchMapping memory) {
        return _suggestedBatch;
    }

    function getPoolRestrictions()
        external
        view
        virtual
        override
        returns (uint64 checkGasLimit, uint64 executionGasLimit, uint96 minBalance)
    {
        return (_gasConfig.checkGasLimit, _gasConfig.executionGasLimit, _gasConfig.minBalance);
    }

    function getFeeConfig()
        external
        view
        virtual
        override
        returns (
            address billingToken,
            uint96 poolCreationFee,
            uint96 maintenanceFee,
            uint32 maintenanceInterval,
            uint32 gracePeriod,
            uint32 closingPeriod
        )
    {
        BillingConfig memory config = _billingConfig;

        return (
            config.billingToken,
            config.poolCreationFee,
            config.maintenanceFee,
            config.maintenanceInterval,
            config.gracePeriod,
            config.closingPeriod
        );
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS - MONEY MANAGEMENT
     *****************************************************************************************************************/

    function withdrawErc20(address token, address to, uint256 amount) external virtual override {
        _authWithdrawErc20();

        IERC20(token).safeTransfer(to, amount);

        emit Erc20Withdrawn(msg.sender, token, to, amount, block.timestamp);
    }

    function withdrawNative(address to, uint256 amount) external virtual override {
        _authWithdrawNative();

        payable(to).transfer(amount);

        emit NativeWithdrawn(msg.sender, to, amount, block.timestamp);
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS - POOL MANAGEMENT
     *****************************************************************************************************************/

    function closePool(address pool) external virtual override {
        _authClosePool();

        IAutomationPoolMinimal(pool).closePool();
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS - POOL CALLBACKS
     *****************************************************************************************************************/

    function poolMaintenanceFeeCollectedCallback(
        uint256 poolId,
        IERC20 billingToken,
        uint256 amount
    ) external virtual override {
        address pool = _pools[poolId - 1];
        if (msg.sender != pool) {
            revert OnlyCallableByPool(pool, msg.sender);
        }

        address factory_ = factory;

        (, uint16 protocolMaintenanceFee, ) = IAutomationRegistryFactory(factory_).getFeeConfig();

        // Calculate protocol fee, rounding up
        uint256 protocolFee = (amount * protocolMaintenanceFee).ceilDiv(10000);
        uint256 feeToRegistry = amount - protocolFee;

        billingToken.safeTransfer(factory_, protocolFee);

        emit PoolMaintenanceFeeCollected(
            poolId,
            pool,
            address(billingToken),
            protocolFee,
            feeToRegistry,
            block.timestamp
        );
    }

    function poolClosedCallback(uint256 poolId) external virtual override {
        address pool = _pools[poolId - 1];
        if (msg.sender != pool) {
            revert OnlyCallableByPool(pool, msg.sender);
        }

        emit PoolClosed(poolId, pool, block.timestamp);
    }

    function poolWorkPerformedCallback(
        uint256 poolId,
        address worker,
        uint256 gasUsed,
        uint256 workerCompensation,
        uint256 registryFee,
        uint256 protocolFee,
        uint256 workerDebt,
        uint256 registryDebt,
        uint256 protocolDebt
    ) external payable virtual override {
        address pool = _pools[poolId - 1];
        if (msg.sender != pool) {
            revert OnlyCallableByPool(pool, msg.sender);
        }

        assert(msg.value == protocolFee + registryFee);

        address factory_ = factory;

        if (protocolFee > 0) {
            (bool protocolFeesPaid, ) = payable(factory_).call{value: protocolFee}("");
            if (!protocolFeesPaid) {
                revert FailedToPayProtocolWorkFees();
            }
        }

        emit PoolWorkPerformed(
            poolId,
            pool,
            worker,
            gasUsed,
            workerCompensation,
            registryFee,
            protocolFee,
            workerDebt,
            registryDebt,
            block.timestamp
        );

        if (workerDebt + registryDebt + protocolDebt > 0) {
            emit PoolGasDebtRecorded(poolId, pool, worker, protocolDebt, registryDebt, workerDebt, block.timestamp);
        }
    }

    function poolGasDebtRecovered(
        uint256 poolId,
        uint256 protocolDebt,
        uint256 registryDebt,
        uint256 workerDebt
    ) external payable virtual override {
        address pool = _pools[poolId - 1];
        if (msg.sender != pool) {
            revert OnlyCallableByPool(pool, msg.sender);
        }

        assert(msg.value == protocolDebt + registryDebt);

        if (protocolDebt > 0) {
            (bool protocolFeesPaid, ) = payable(factory).call{value: protocolDebt}("");
            if (!protocolFeesPaid) {
                revert FailedToPayProtocolWorkFees();
            }
        }

        emit PoolGasDebtRecovered(poolId, pool, protocolDebt, registryDebt, workerDebt, block.timestamp);
    }

    /******************************************************************************************************************
     * PUBLIC FUNCTIONS
     *****************************************************************************************************************/

    function getGasData()
        public
        view
        virtual
        override
        returns (
            uint256 gasPrice,
            uint256 overhead,
            uint16 registryFee,
            address l1GasCalculator,
            uint256 gasPremium,
            uint16 protocolFee
        )
    {
        GasConfig memory config = _gasConfig;

        if (config.gasPriceOracle != address(0)) {
            // Note: We ignore freshness b/c we don't want to revert if the oracle is stale
            gasPrice = IPriceOracle(config.gasPriceOracle).consultPrice(GAS_PRICE_TOKEN);
        } else {
            gasPrice = tx.gasprice;
        }

        // Calculate the gas price with the premium
        overhead = config.gasOverhead;
        registryFee = config.workFee;
        l1GasCalculator = config.l1GasCalculator;
        gasPremium = config.gasPricePremium;

        (, , protocolFee) = IAutomationRegistryFactory(factory).getFeeConfig();
    }

    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        if (role == Roles.PROTOCOL_ADMIN) {
            // The factory manages the protocol admin role
            return IAccessControl(factory).hasRole(role, account);
        }

        return super.hasRole(role, account);
    }

    /**
     * Gets the address of the contract that manages the specified role.
     *
     * @param role The hash of the role to check.
     */
    function getRoleManagementAddress(bytes32 role) public view virtual override returns (address) {
        if (role == Roles.PROTOCOL_ADMIN) {
            // The factory manages the protocol admin role
            return factory;
        }

        if (getRoleAdmin(role) == bytes32(0)) {
            // This is the default admin role, which is not used and indicates that the role is not supported.
            revert RoleNotSupported(role);
        }

        return address(this);
    }

    /******************************************************************************************************************
     * INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function _setBillingConfig(BillingConfig calldata newConfig) internal virtual {
        if (keccak256(abi.encode(_billingConfig)) == keccak256(abi.encode(newConfig))) {
            revert BillingConfigNotChanged();
        }

        // Check general billing restrictions
        (
            uint32 minMaintenanceInterval,
            uint32 maxMaintenanceInterval,
            uint32 minGracePeriod,
            uint32 maxGracePeriod,
            uint32 minClosingPeriod,
            uint32 maxClosingPeriod
        ) = IAutomationRegistryFactory(factory).getRegistryBillingRestrictions();
        if (newConfig.maintenanceInterval < minMaintenanceInterval) {
            revert MaintenanceIntervalTooLow(minMaintenanceInterval, newConfig.maintenanceInterval);
        }
        if (newConfig.maintenanceInterval > maxMaintenanceInterval) {
            revert MaintenanceIntervalTooHigh(maxMaintenanceInterval, newConfig.maintenanceInterval);
        }
        if (newConfig.gracePeriod < minGracePeriod) {
            revert GracePeriodTooLow(minGracePeriod, newConfig.gracePeriod);
        }
        if (newConfig.gracePeriod > maxGracePeriod) {
            revert GracePeriodTooHigh(maxGracePeriod, newConfig.gracePeriod);
        }
        if (newConfig.closingPeriod < minClosingPeriod) {
            revert ClosingPeriodTooLow(minClosingPeriod, newConfig.closingPeriod);
        }
        if (newConfig.closingPeriod > maxClosingPeriod) {
            revert ClosingPeriodTooHigh(maxClosingPeriod, newConfig.closingPeriod);
        }

        // Calculate new maintenance fee per day
        uint256 maintenanceFeePerDayL = (uint256(newConfig.maintenanceFee) * 1 days) / newConfig.maintenanceInterval;
        uint256 maintenanceFeePerDayH = (uint256(newConfig.maintenanceFee) * 1 days).ceilDiv(
            newConfig.maintenanceInterval
        );

        // Check billing token restrictions
        (
            uint96 minPoolCreationFee,
            uint96 maxPoolCreationFee,
            uint96 minMaintenanceFeePerDay,
            uint96 maxMaintenanceFeePerDay
        ) = IAutomationRegistryFactory(factory).getBillingTokenRestrictions(newConfig.billingToken);
        if (newConfig.poolCreationFee < minPoolCreationFee) {
            revert PoolCreationFeeTooLow(minPoolCreationFee, newConfig.poolCreationFee);
        }
        if (newConfig.poolCreationFee > maxPoolCreationFee) {
            revert PoolCreationFeeTooHigh(maxPoolCreationFee, newConfig.poolCreationFee);
        }
        if (maintenanceFeePerDayL < minMaintenanceFeePerDay) {
            revert MaintenanceFeeTooLow(minMaintenanceFeePerDay, maintenanceFeePerDayL);
        }
        if (maintenanceFeePerDayH > maxMaintenanceFeePerDay) {
            revert MaintenanceFeeTooHigh(maxMaintenanceFeePerDay, maintenanceFeePerDayH);
        }

        if (!IAutomationRegistryFactory(factory).isValidBillingToken(newConfig.billingToken)) {
            revert InvalidBillingToken(newConfig.billingToken);
        }

        BillingConfig memory oldConfig = _billingConfig;

        _billingConfig = newConfig;

        emit BillingConfigUpdated(oldConfig, newConfig, block.timestamp);
    }

    function _setGasConfig(GasConfig calldata newConfig) internal virtual {
        if (keccak256(abi.encode(_gasConfig)) == keccak256(abi.encode(newConfig))) {
            revert ConfigNotChanged();
        }

        (
            uint32 minGasPricePremium,
            uint32 maxGasPricePremium,
            uint64 maxGasOverhead,
            uint96 maxMinBalance,
            uint16 minWorkFee,
            uint16 maxWorkFee
        ) = IAutomationRegistryFactory(factory).getRegistryRestrictions();
        if (newConfig.gasPricePremium < minGasPricePremium) {
            revert GasPricePremiumTooLow(minGasPricePremium, newConfig.gasPricePremium);
        }
        if (newConfig.gasPricePremium > maxGasPricePremium) {
            revert GasPricePremiumTooHigh(maxGasPricePremium, newConfig.gasPricePremium);
        }
        if (newConfig.gasOverhead > maxGasOverhead) {
            revert GasOverheadTooHigh(maxGasOverhead, newConfig.gasOverhead);
        }
        if (newConfig.minBalance > maxMinBalance) {
            revert MinBalanceTooHigh(maxMinBalance, newConfig.minBalance);
        }
        if (newConfig.workFee < minWorkFee) {
            revert WorkFeeTooLow(minWorkFee, newConfig.workFee);
        }
        if (newConfig.workFee > maxWorkFee) {
            revert WorkFeeTooHigh(maxWorkFee, newConfig.workFee);
        }

        if (!IAutomationRegistryFactory(factory).isValidGasPriceOracle(newConfig.gasPriceOracle)) {
            revert InvalidGasPriceOracle(newConfig.gasPriceOracle);
        }

        if (!IAutomationRegistryFactory(factory).isValidL1GasCalculator(newConfig.l1GasCalculator)) {
            revert InvalidL1GasCalculator(newConfig.l1GasCalculator);
        }

        GasConfig memory oldConfig = _gasConfig;

        _gasConfig = newConfig;

        emit GasConfigUpdated(oldConfig, newConfig, block.timestamp);
    }

    function _setWorkerConfig(WorkerConfig calldata newConfig) internal virtual {
        if (keccak256(abi.encode(_workerConfig)) == keccak256(abi.encode(newConfig))) {
            revert WorkerConfigNotChanged();
        }

        if (newConfig.pollingIntervalMs == 0) {
            revert InvalidPollingInterval(newConfig.pollingIntervalMs);
        }

        WorkerConfig memory oldConfig = _workerConfig;

        _workerConfig = newConfig;

        emit WorkerConfigUpdated(oldConfig, newConfig, block.timestamp);
    }

    function _setMetadata(Metadata calldata newMetadata) internal virtual {
        if (keccak256(abi.encode(_metadata)) == keccak256(abi.encode(newMetadata))) {
            revert MetadataNotChanged();
        }

        Metadata memory oldMetadata = _metadata;

        _metadata = newMetadata;

        emit MetadataUpdated(oldMetadata, newMetadata, block.timestamp);
    }

    function _setSuggestedBatch(AutomationPoolTypes.BatchMapping calldata batch) internal virtual {
        AutomationPoolTypes.BatchMapping memory oldBatch = _suggestedBatch;

        if (keccak256(abi.encode(_suggestedBatch)) == keccak256(abi.encode(batch))) {
            revert SuggestedBatchNotChanged();
        }

        _suggestedBatch = batch;

        emit SuggestedBatchUpdated(oldBatch, batch, block.timestamp);
    }

    function _collectPoolCreationFee() internal virtual returns (address billingToken, uint256 amountPaid) {
        BillingConfig memory config = _billingConfig;
        uint256 poolCreationFee = config.poolCreationFee;
        if (poolCreationFee > 0) {
            IERC20(config.billingToken).safeTransferFrom(msg.sender, address(this), poolCreationFee);
        }

        return (config.billingToken, poolCreationFee);
    }

    function _grantRole(bytes32 role, address account) internal virtual override returns (bool) {
        if (role == Roles.PROTOCOL_ADMIN) {
            // The factory manages the protocol admin role
            revert RoleManagedByContract(role, factory);
        }

        return super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
        if (role == Roles.PROTOCOL_ADMIN) {
            // The factory manages the protocol admin role
            revert RoleManagedByContract(role, factory);
        }

        return super._revokeRole(role, account);
    }

    /******************************************************************************************************************
     * AUTHORIZATION
     *****************************************************************************************************************/

    function _authSetGasConfig() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}

    function _authSetBillingConfig() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}

    function _authSetWorkerConfig() internal view virtual onlyRole(Roles.WORKER_MANAGER) {}

    function _authSetMetadata() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}

    function _authCreatePool() internal view virtual onlyRoleOrOpenRole(Roles.REGISTRY_POOL_DEPLOYER) {}

    function _authClosePool() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}

    function _authWithdrawPoolGasFunds() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authSetPoolClosingWithdrawalHold() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}

    function _authWithdrawErc20() internal view virtual onlyRole(Roles.REGISTRY_FINANCE_MANAGER) {}

    function _authWithdrawNative() internal view virtual onlyRole(Roles.REGISTRY_FINANCE_MANAGER) {}

    function _authSetSuggestedBatch() internal view virtual onlyRole(Roles.REGISTRY_MANAGER) {}
}
