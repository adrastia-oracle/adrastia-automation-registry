// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AutomationPoolTypes} from "../pool/AutomationPoolTypes.sol";

interface IAutomationRegistry {
    /******************************************************************************************************************
     * TYPES
     *****************************************************************************************************************/

    struct GasConfig {
        // SLOT 1 - 256 bits
        /**
         * @notice The address of the gas price oracle. If set to the zero address, tx.gasprice will be used.
         */
        address gasPriceOracle;
        /**
         * @notice The premium to be added to the gas price, in basis points. Ex: 100 = 1% premium.
         */
        uint32 gasPricePremium;
        /**
         * @notice The overhead to be added to the gas used, in gas units.
         */
        uint64 gasOverhead;
        // SLOT 2 - 240 bits
        /**
         * @notice The maximum gas limit of the executor to check for work.
         */
        uint64 checkGasLimit;
        /**
         * @notice The maximum gas limit of the executor to perform work.
         */
        uint64 executionGasLimit;
        /**
         * @notice The minimum balance required to execute the automation, in wei.
         */
        uint96 minBalance;
        /**
         * @notice The fee for performing work, in basis points, as a portion of the gas premium paid by the pool after
         * protocol fees are taken.
         */
        uint16 workFee;
        // SLOT 3 - 160 bits
        /**
         * @notice The address of the L1 gas calculator.
         */
        address l1GasCalculator;
    }

    struct BillingConfig {
        // SLOT 1 - 256 bits
        /**
         * @notice The fee for creating a pool, in the billing token's smallest unit of account.
         */
        uint96 poolCreationFee;
        /**
         * @notice The maintenance fee for the pool, in the billing token's smallest unit of account.
         */
        uint96 maintenanceFee;
        /**
         * @notice The interval for maintenance fees, in seconds. A.k.a. the billing period.
         */
        uint32 maintenanceInterval;
        /**
         * @notice The grace period for maintenance fees, in seconds. This is the amount of time that the pool has to
         * pay the maintenance fee before it gets closed.
         */
        uint32 gracePeriod;
        // SLOT 2
        /**
         * @notice The closing period for the pool, in seconds. This is the amount of time that the pool operator must
         * wait before they can withdraw the remaining balance after initiating a close.
         */
        uint32 closingPeriod;
        /**
         * @notice The token used for billing.
         */
        address billingToken;
    }

    struct WorkerConfig {
        /**
         * @notice The interval that workers use to check for work, in milliseconds.
         * @dev Workers should conform to this interval. It's not possible to enforce onchain.
         */
        uint32 pollingIntervalMs;
    }

    struct Metadata {
        /**
         * @notice The name of the registry.
         */
        string name;
        /**
         * @notice The description of the registry.
         */
        string description;
        /**
         * @notice The type of the pools that can be created by this registry.
         */
        uint16 poolType;
    }

    /******************************************************************************************************************
     * EVENTS - POOL LIFECYCLE
     *****************************************************************************************************************/

    event PoolCreated(address indexed creator, uint256 indexed id, address indexed pool, uint256 timestamp);

    event PoolClosed(uint256 indexed id, address indexed pool, uint256 timestamp);

    /******************************************************************************************************************
     * EVENTS - POOL DEBT
     *****************************************************************************************************************/

    event PoolGasDebtRecorded(
        uint256 indexed id,
        address indexed pool,
        address indexed worker,
        uint256 protocolDebt,
        uint256 registryDebt,
        uint256 workerDebt,
        uint256 timestamp
    );

    event PoolGasDebtRecovered(
        uint256 indexed id,
        address indexed pool,
        uint256 protocolDebt,
        uint256 registryDebt,
        uint256 workerDebt,
        uint256 timestamp
    );

    /******************************************************************************************************************
     * EVENTS - POOL FEES AND WORK
     *****************************************************************************************************************/

    event PoolCreationFeeCollected(
        uint256 indexed id,
        address indexed pool,
        address indexed token,
        uint256 protocolAmount,
        uint256 registryAmount,
        uint256 timestamp
    );

    event PoolMaintenanceFeeCollected(
        uint256 indexed id,
        address indexed pool,
        address indexed token,
        uint256 protocolAmount,
        uint256 registryAmount,
        uint256 timestamp
    );

    event PoolWorkPerformed(
        uint256 indexed id,
        address indexed pool,
        address indexed worker,
        uint256 gasUsed,
        uint256 workerCompensation,
        uint256 registryFee,
        uint256 protocolFee,
        uint256 workerDebt,
        uint256 registryDebt, // Before paying the protocol fees
        uint256 timestamp
    );

    /******************************************************************************************************************
     * EVENTS - CONFIG
     *****************************************************************************************************************/

    event BillingConfigUpdated(BillingConfig oldConfig, BillingConfig newConfig, uint256 timestamp);

    event GasConfigUpdated(GasConfig oldConfig, GasConfig newConfig, uint256 timestamp);

    event WorkerConfigUpdated(WorkerConfig oldConfig, WorkerConfig newConfig, uint256 timestamp);

    event MetadataUpdated(Metadata oldMetadata, Metadata newMetadata, uint256 timestamp);

    event SuggestedBatchUpdated(
        AutomationPoolTypes.BatchMapping oldBatch,
        AutomationPoolTypes.BatchMapping newBatch,
        uint256 timestamp
    );

    /******************************************************************************************************************
     * EVENTS - FUND WITHDRAWAL
     *****************************************************************************************************************/

    event Erc20Withdrawn(
        address indexed caller,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event NativeWithdrawn(address indexed caller, address indexed to, uint256 amount, uint256 timestamp);

    /******************************************************************************************************************
     * ERRORS
     *****************************************************************************************************************/

    error MissingPoolBeacon();

    error OnlyCallableByPool(address pool, address caller);

    error ConfigNotChanged();

    error BillingConfigNotChanged();

    error WorkerConfigNotChanged();

    error MetadataNotChanged();

    error SuggestedBatchNotChanged();

    error RoleManagedByContract(bytes32 role, address contractAddress);

    error FailedToPayProtocolWorkFees();

    error GasPricePremiumTooLow(uint32 minGasPricePremium, uint32 gasPricePremium);

    error GasPricePremiumTooHigh(uint32 maxGasPricePremium, uint32 gasPricePremium);

    error GasOverheadTooHigh(uint64 maxGasOverhead, uint64 gasOverhead);

    error MinBalanceTooHigh(uint96 maxMinBalance, uint96 minBalance);

    error WorkFeeTooLow(uint16 minWorkFee, uint16 workFee);

    error WorkFeeTooHigh(uint16 maxWorkFee, uint16 workFee);

    error InvalidPollingInterval(uint32 pollingIntervalMs);

    error InvalidGasPriceOracle(address gasPriceOracle);

    error InvalidL1GasCalculator(address l1GasCalculator);

    error MaintenanceIntervalTooLow(uint32 minMaintenanceInterval, uint32 maintenanceInterval);

    error MaintenanceIntervalTooHigh(uint32 maxMaintenanceInterval, uint32 maintenanceInterval);

    error GracePeriodTooLow(uint32 minGracePeriod, uint32 gracePeriod);

    error GracePeriodTooHigh(uint32 maxGracePeriod, uint32 gracePeriod);

    error ClosingPeriodTooLow(uint32 minClosingPeriod, uint32 closingPeriod);

    error ClosingPeriodTooHigh(uint32 maxClosingPeriod, uint32 closingPeriod);

    error PoolCreationFeeTooLow(uint96 minPoolCreationFee, uint96 poolCreationFee);

    error PoolCreationFeeTooHigh(uint96 maxPoolCreationFee, uint96 poolCreationFee);

    error MaintenanceFeeTooLow(uint96 minMaintenanceFeePerDay, uint256 maintenanceFeePerDay);

    error MaintenanceFeeTooHigh(uint96 maxMaintenanceFeePerDay, uint256 maintenanceFeePerDay);

    error InvalidBillingToken(address billingToken);

    error RoleNotSupported(bytes32 role);

    error FailedToInitializePool();

    /******************************************************************************************************************
     * FUNCTIONS - FIXED PROPERTY GETTERS
     *****************************************************************************************************************/

    function id() external view returns (uint256);

    function factory() external view returns (address);

    function diamond() external view returns (address);

    function poolDiamond() external view returns (address);

    function poolType() external view returns (uint16);

    function poolBeacon() external view returns (address);

    function executorBeacon() external view returns (address);

    /******************************************************************************************************************
     * FUNCTIONS - VARIABLE PROPERTY GETTERS
     *****************************************************************************************************************/

    function name() external view returns (string memory);

    function description() external view returns (string memory);

    /******************************************************************************************************************
     * FUNCTIONS - POOLS
     *****************************************************************************************************************/

    function closePool(address pool) external;

    function createPool() external;

    function getPool(uint256 poolId) external view returns (address);

    function getPools() external view returns (address[] memory);

    function getPoolsCount() external view returns (uint256);

    /******************************************************************************************************************
     * FUNCTIONS - CONFIG GETTERS
     *****************************************************************************************************************/

    function getGasConfig() external view returns (GasConfig memory);

    function getBillingConfig() external view returns (BillingConfig memory);

    function getWorkerConfig() external view returns (WorkerConfig memory);

    function getSuggestedBatch() external view returns (AutomationPoolTypes.BatchMapping memory);

    function getGasData()
        external
        view
        returns (
            uint256 price,
            uint256 overhead,
            uint16 registryFee,
            address l1GasCalculator,
            uint256 gasPremium,
            uint16 protocolFee
        );

    /**
     * @notice Get the pool restrictions for the automation system.
     * @return checkGasLimit The maximum gas limit to check for work.
     * @return executionGasLimit The maximum gas limit to perform work.
     * @return minBalance The minimum balance required to execute the automation.
     */
    function getPoolRestrictions()
        external
        view
        returns (uint64 checkGasLimit, uint64 executionGasLimit, uint96 minBalance);

    function getFeeConfig()
        external
        view
        returns (
            address billingToken,
            uint96 poolCreationFee,
            uint96 maintenanceFee,
            uint32 maintenanceInterval,
            uint32 gracePeriod,
            uint32 closingPeriod
        );

    /******************************************************************************************************************
     * FUNCTIONS - FUND MANAGEMENT
     *****************************************************************************************************************/

    function withdrawErc20(address token, address to, uint256 amount) external;

    function withdrawNative(address to, uint256 amount) external;

    /******************************************************************************************************************
     * CALLBACKS - FROM POOLS
     *****************************************************************************************************************/

    /**
     * @notice A callback to notify the registry that maintenance fees have been collected.
     * @dev Only callable by the pool.
     * @param poolId The ID of the pool that collected the fees.
     */
    function poolMaintenanceFeeCollectedCallback(uint256 poolId, IERC20 billingToken, uint256 amount) external;

    /**
     * @notice A callback to notify the registry that a pool has been closed.
     * @dev Only callable by the pool.
     * @param poolId The ID of the pool that was closed.
     */
    function poolClosedCallback(uint256 poolId) external;

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
    ) external payable;

    function poolGasDebtRecovered(
        uint256 poolId,
        uint256 protocolDebt,
        uint256 registryDebt,
        uint256 workerDebt
    ) external payable;
}
