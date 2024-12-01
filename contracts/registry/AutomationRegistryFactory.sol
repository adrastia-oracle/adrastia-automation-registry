// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessControl, AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAutomationRegistryFactory} from "./IAutomationRegistryFactory.sol";
import {AutomationRegistry} from "./AutomationRegistry.sol";
import {StandardRoleManagement} from "../access/StandardRoleManagement.sol";
import {Roles} from "../access/Roles.sol";

contract AutomationRegistryFactory is IAutomationRegistryFactory, Initializable, StandardRoleManagement {
    using SafeERC20 for IERC20;

    /******************************************************************************************************************
     * TYPES
     *****************************************************************************************************************/

    struct FeeConfig {
        /**
         * @notice The fee collected from the registry for creating a pool, in basis points.
         */
        uint16 poolCreationFee;
        /**
         * @notice The fee collected from the registry for maintenance, in basis points.
         */
        uint16 maintenanceFee;
        /**
         * @notice The fee collected from the registry for performing work, in basis points.
         */
        uint16 workFee;
    }

    struct RegistryRestrictions {
        /**
         * @notice The minimum gas price premium that registries can set, in percentage points.
         */
        uint16 minGasPricePremium;
        /**
         * @notice The maximum gas price premium that registries can set, in percentage points.
         */
        uint16 maxGasPricePremium;
        /**
         * @notice The maximum gas overhead that registries can set, in gas units.
         */
        uint64 maxGasOverhead;
        /**
         * @notice The maximum minimum balance that registries can set, in wei.
         */
        uint96 maxMinBalance;
        /**
         * @notice The minimum work fee that registries can set, in basis points.
         */
        uint16 minWorkFee;
        /**
         * @notice The maximum work fee that registries can set, in basis points.
         */
        uint16 maxWorkFee;
    }

    struct RegistryBillingRestrictions {
        /**
         * @notice The minimum maintenance interval that registries can set, in seconds.
         */
        uint32 minMaintenanceInterval;
        /**
         * @notice The maximum maintenance interval that registries can set, in seconds.
         */
        uint32 maxMaintenanceInterval;
        /**
         * @notice The minimum grace period that registries can set, in seconds.
         */
        uint32 minGracePeriod;
        /**
         * @notice The maximum grace period that registries can set, in seconds.
         */
        uint32 maxGracePeriod;
        /**
         * @notice The minimum closing period that registries can set, in seconds.
         */
        uint32 minClosingPeriod;
        /**
         * @notice The maximum closing period that registries can set, in seconds.
         */
        uint32 maxClosingPeriod;
    }

    struct BillingTokenRestrictions {
        /**
         * @notice The minimum pool creation fee that registries can set, in the smallest unit of account.
         */
        uint96 minPoolCreationFee;
        /**
         * @notice The maximum pool creation fee that registries can set, in the smallest unit of account.
         */
        uint96 maxPoolCreationFee;
        /**
         * @notice The minimum maintenance fee that registries can set, in the smallest unit of account per day.
         */
        uint96 minMaintenanceFeePerDay;
        /**
         * @notice The maximum maintenance fee that registries can set, in the smallest unit of account per day.
         */
        uint96 maxMaintenanceFeePerDay;
    }

    /******************************************************************************************************************
     * STORAGE
     *****************************************************************************************************************/

    /**
     * @notice The beacon that contains the implementation for registries.
     */
    address public registryBeacon;

    /**
     * @notice The beacon that contains the implementation for pools.
     */
    address public poolBeacon;

    /**
     * @notice The beacon that contains the implementation for executors.
     */
    address public executorBeacon;

    /**
     * @notice The address of the registry diamond contract.
     */
    address public registryDiamond;

    /**
     * @notice The address of the pool diamond contract.
     */
    address public poolDiamond;

    /**
     * @notice The list of registries that have been created.
     * @dev The index of a registry in this array is its ID.
     */
    address[] internal _registries;

    /**
     * @notice The fee configuration for the protocol.
     */
    FeeConfig internal _feeConfig;

    /**
     * @notice The restrictions for registries.
     */
    RegistryRestrictions internal _registryRestrictions;

    /**
     * @notice The billing restrictions for registries.
     */
    RegistryBillingRestrictions internal _registryBillingRestrictions;

    /**
     * @notice The whitelist of gas price oracles that can be used by registries.
     */
    mapping(address => bool) internal _gasOracleWhitelist;

    /**
     * @notice The whitelist of L1 gas calculators that can be used by registries.
     */
    mapping(address => bool) internal _l1GasCalculatorWhitelist;

    /**
     * @notice The billing restrictions for tokens.
     * @dev The key is the token address.
     */
    mapping(address => BillingTokenRestrictions) internal _billingTokenRestrictions;

    /**
     * @notice The list of gas price oracles that can be used by registries.
     */
    address[] internal _gasPriceOracles;

    /**
     * @notice The list of L1 gas calculators that can be used by registries.
     */
    address[] internal _l1GasCalculators;

    /**
     * @notice The list of billing tokens that can be used by registries.
     */
    address[] internal _billingTokens;

    /******************************************************************************************************************
     * EVENTS
     *****************************************************************************************************************/

    event RegistryCreated(address indexed creator, address indexed registry, uint256 timestamp);

    event FeeConfigUpdated(FeeConfig oldConfig, FeeConfig newConfig, uint256 timestamp);

    event RegistryRestrictionsUpdated(
        RegistryRestrictions oldRestrictions,
        RegistryRestrictions newRestrictions,
        uint256 timestamp
    );

    event RegistryBillingRestrictionsUpdated(
        RegistryBillingRestrictions oldRestrictions,
        RegistryBillingRestrictions newRestrictions,
        uint256 timestamp
    );

    event BillingTokenRestrictionsUpdated(
        address indexed token,
        BillingTokenRestrictions oldRestrictions,
        BillingTokenRestrictions newRestrictions,
        uint256 timestamp
    );

    event GasPriceOracleValidityUpdated(address indexed oracle, bool isValid, uint256 timestamp);

    event L1GasCalculatorValidityUpdated(address indexed calculator, bool isValid, uint256 timestamp);

    /******************************************************************************************************************
     * ERRORS
     *****************************************************************************************************************/

    error NotAnAdmin(address account);

    error ProtocolAdminDoesntHaveRole(bytes32 role);

    error FeeConfigNotChanged();

    error RegistryRestrictionsNotChanged();

    error RegistryBillingRestrictionsNotChanged();

    error BillingTokenRestrictionsNotChanged();

    error GasPriceOracleValidityNotChanged();

    error L1GasCalculatorValidityNoChanged();

    error InvalidBillingToken(address token);

    error MinGasPricePremiumGreaterThanMax(uint16 minGasPricePremium, uint16 maxGasPricePremium);

    error MinWorkFeeGreaterThanMax(uint16 minWorkFee, uint16 maxWorkFee);

    error MaxWorkFeeTooHigh(uint16 maxWorkFee);

    error InvalidAdmin(address admin);

    error MinMaintenanceFeeCannotBeZero();

    error BillingRestrictionsNotSet();

    /******************************************************************************************************************
     * INITIALIZER
     *****************************************************************************************************************/

    function initialize(
        address protocolAdmin_,
        address factoryAdmin,
        address registryImplementation,
        address poolImplementation,
        address executorImplementation,
        address registryDiamond_,
        address poolDiamond_
    ) public virtual initializer {
        _initializeRoles(protocolAdmin_, factoryAdmin);

        registryBeacon = address(new UpgradeableBeacon(registryImplementation, protocolAdmin_));
        poolBeacon = address(new UpgradeableBeacon(poolImplementation, protocolAdmin_));
        executorBeacon = address(new UpgradeableBeacon(executorImplementation, protocolAdmin_));

        registryDiamond = registryDiamond_;
        poolDiamond = poolDiamond_;
    }

    function _initializeRoles(address protocolAdmin_, address factoryAdmin) internal virtual {
        // PROTOCOL_ADMIN manages itself
        _setRoleAdmin(Roles.PROTOCOL_ADMIN, Roles.PROTOCOL_ADMIN);

        // PROTOCOL_ADMIN manages FACTORY_ADMIN
        _setRoleAdmin(Roles.FACTORY_ADMIN, Roles.PROTOCOL_ADMIN);

        // FACTORY_ADMIN manages FACTORY_MANAGER
        _setRoleAdmin(Roles.FACTORY_MANAGER, Roles.FACTORY_ADMIN);

        // FACTORY_MANAGER manages FACTORY_REGISTRY_DEPLOYER
        _setRoleAdmin(Roles.FACTORY_REGISTRY_DEPLOYER, Roles.FACTORY_MANAGER);

        // Grant all roles to the protocol admin
        _grantRole(Roles.PROTOCOL_ADMIN, protocolAdmin_);
        _grantRole(Roles.FACTORY_ADMIN, protocolAdmin_);
        _grantRole(Roles.FACTORY_MANAGER, protocolAdmin_);
        _grantRole(Roles.FACTORY_REGISTRY_DEPLOYER, protocolAdmin_);

        // Grant all factory roles to the factory admin
        _grantRole(Roles.FACTORY_ADMIN, factoryAdmin);
        _grantRole(Roles.FACTORY_MANAGER, factoryAdmin);
        _grantRole(Roles.FACTORY_REGISTRY_DEPLOYER, factoryAdmin);
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    receive() external payable {
        // IT'S PAYDAY FELLAS
    }

    function getRegistry(uint256 id) external view virtual returns (address) {
        return _registries[id - 1];
    }

    function getRegistries() external view virtual returns (address[] memory) {
        return _registries;
    }

    function getRegistriesCount() external view virtual returns (uint256) {
        return _registries.length;
    }

    function createRegistry(
        address admin,
        AutomationRegistry.Metadata calldata initialMetadata,
        AutomationRegistry.GasConfig calldata initialGasConfig,
        AutomationRegistry.BillingConfig calldata initialBillingConfig,
        AutomationRegistry.WorkerConfig calldata initialWorkerConfig
    ) external virtual returns (address) {
        _authCreateRegistry();

        // Basic validation
        if (admin == address(0)) {
            revert InvalidAdmin(admin);
        }
        // Note that the AutomationRegistry contract will validate the rest of the parameters

        uint256 registryId = _registries.length + 1;

        BeaconProxy proxy = new BeaconProxy(registryBeacon, hex"");
        _registries.push(address(proxy));

        AutomationRegistry(payable(address(proxy))).initialize(
            registryId,
            registryDiamond,
            admin,
            address(this),
            poolBeacon,
            executorBeacon,
            poolDiamond,
            initialMetadata,
            initialGasConfig,
            initialBillingConfig,
            initialWorkerConfig
        );

        emit RegistryCreated(msg.sender, address(proxy), block.timestamp);

        return address(proxy);
    }

    function setFeeConfig(FeeConfig calldata config) external virtual {
        _authSetFeeConfig();

        _setFeeConfig(config);
    }

    function setRegistryRestrictions(RegistryRestrictions calldata restrictions) external virtual {
        _authSetRegistryRestrictions();

        _setRegistryRestrictions(restrictions);
    }

    function setRegistryBillingRestrictions(RegistryBillingRestrictions calldata restrictions) external virtual {
        _authSetRegistryBillingRestrictions();

        _setRegistryBillingRestrictions(restrictions);
    }

    function setBillingTokenRestrictions(
        address token,
        BillingTokenRestrictions calldata restrictions
    ) external virtual {
        _authSetBillingTokenRestrictions();

        _setBillingTokenRestrictions(token, restrictions);
    }

    function setGasPriceOracleValidity(address oracle, bool isValid) external virtual {
        _authSetGasPriceOracleValidity();

        _setGasPriceOracleValidity(oracle, isValid);
    }

    function setL1GasCalculatorValidity(address calculator, bool isValid) external virtual {
        _authSetGasPriceOracleValidity();

        _setL1GasCalculatorValidity(calculator, isValid);
    }

    function feeConfig()
        external
        view
        virtual
        override
        returns (uint16 poolCreationFee, uint16 maintenanceFee, uint16 workFee)
    {
        FeeConfig memory config = _feeConfig;

        return (config.poolCreationFee, config.maintenanceFee, config.workFee);
    }

    function registryRestrictions()
        external
        view
        virtual
        override
        returns (
            uint16 minGasPricePremium,
            uint16 maxGasPricePremium,
            uint64 maxGasOverhead,
            uint96 maxMinBalance,
            uint16 minWorkFee,
            uint16 maxWorkFee
        )
    {
        RegistryRestrictions memory restrictions = _registryRestrictions;

        return (
            restrictions.minGasPricePremium,
            restrictions.maxGasPricePremium,
            restrictions.maxGasOverhead,
            restrictions.maxMinBalance,
            restrictions.minWorkFee,
            restrictions.maxWorkFee
        );
    }

    function registryBillingRestrictions()
        external
        view
        virtual
        override
        returns (
            uint32 minMaintenanceInterval,
            uint32 maxMaintenanceInterval,
            uint32 minGracePeriod,
            uint32 maxGracePeriod,
            uint32 minClosingPeriod,
            uint32 maxClosingPeriod
        )
    {
        RegistryBillingRestrictions memory restrictions = _registryBillingRestrictions;
        if (restrictions.minMaintenanceInterval == 0) {
            revert BillingRestrictionsNotSet();
        }

        return (
            restrictions.minMaintenanceInterval,
            restrictions.maxMaintenanceInterval,
            restrictions.minGracePeriod,
            restrictions.maxGracePeriod,
            restrictions.minClosingPeriod,
            restrictions.maxClosingPeriod
        );
    }

    function billingTokenRestrictions(
        address token
    )
        external
        view
        virtual
        override
        returns (
            uint96 minPoolCreationFee,
            uint96 maxPoolCreationFee,
            uint96 minMaintenanceFeePerDay,
            uint96 maxMaintenanceFeePerDay
        )
    {
        BillingTokenRestrictions memory restrictions = _billingTokenRestrictions[token];
        if (restrictions.maxMaintenanceFeePerDay == 0) {
            revert InvalidBillingToken(token);
        }

        return (
            restrictions.minPoolCreationFee,
            restrictions.maxPoolCreationFee,
            restrictions.minMaintenanceFeePerDay,
            restrictions.maxMaintenanceFeePerDay
        );
    }

    function isValidGasPriceOracle(address oracle) external view virtual override returns (bool) {
        return _gasOracleWhitelist[oracle];
    }

    function isValidL1GasCalculator(address calculator) external view virtual override returns (bool) {
        return _l1GasCalculatorWhitelist[calculator];
    }

    function isValidBillingToken(address token) external view virtual override returns (bool) {
        return _billingTokenRestrictions[token].maxMaintenanceFeePerDay > 0;
    }

    function getGasPriceOracles() external view virtual returns (address[] memory) {
        return _gasPriceOracles;
    }

    function getL1GasCalculators() external view virtual returns (address[] memory) {
        return _l1GasCalculators;
    }

    function getBillingTokens() external view virtual returns (address[] memory) {
        return _billingTokens;
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS - MONEY MANAGEMENT
     *****************************************************************************************************************/

    function withdrawErc20(address token, address to, uint256 amount) external virtual {
        _authWithdrawErc20();

        IERC20(token).safeTransfer(to, amount);
    }

    function withdrawNative(address to, uint256 amount) external virtual {
        _authWithdrawNative();

        payable(to).transfer(amount);
    }

    /******************************************************************************************************************
     * INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function _setFeeConfig(FeeConfig calldata config) internal virtual {
        FeeConfig memory oldConfig = _feeConfig;
        if (keccak256(abi.encode(config)) == keccak256(abi.encode(oldConfig))) {
            revert FeeConfigNotChanged();
        }

        _feeConfig = config;

        emit FeeConfigUpdated(oldConfig, config, block.timestamp);
    }

    function _setRegistryRestrictions(RegistryRestrictions calldata restrictions) internal virtual {
        RegistryRestrictions memory oldRestrictions = _registryRestrictions;
        if (keccak256(abi.encode(restrictions)) == keccak256(abi.encode(oldRestrictions))) {
            revert RegistryRestrictionsNotChanged();
        }

        if (restrictions.minGasPricePremium > restrictions.maxGasPricePremium) {
            revert MinGasPricePremiumGreaterThanMax(restrictions.minGasPricePremium, restrictions.maxGasPricePremium);
        }
        if (restrictions.minWorkFee > restrictions.maxWorkFee) {
            revert MinWorkFeeGreaterThanMax(restrictions.minWorkFee, restrictions.maxWorkFee);
        }
        if (restrictions.maxWorkFee > 10000) {
            // maxWorkFee > 100%
            revert MaxWorkFeeTooHigh(restrictions.maxWorkFee);
        }

        _registryRestrictions = restrictions;

        emit RegistryRestrictionsUpdated(oldRestrictions, restrictions, block.timestamp);
    }

    function _setRegistryBillingRestrictions(RegistryBillingRestrictions calldata restrictions) internal virtual {
        RegistryBillingRestrictions memory oldRestrictions = _registryBillingRestrictions;
        if (keccak256(abi.encode(restrictions)) == keccak256(abi.encode(oldRestrictions))) {
            revert RegistryBillingRestrictionsNotChanged();
        }

        if (restrictions.minMaintenanceInterval == 0) {
            revert MinMaintenanceFeeCannotBeZero();
        }

        _registryBillingRestrictions = restrictions;

        emit RegistryBillingRestrictionsUpdated(oldRestrictions, restrictions, block.timestamp);
    }

    function _setBillingTokenRestrictions(
        address token,
        BillingTokenRestrictions calldata restrictions
    ) internal virtual {
        BillingTokenRestrictions memory oldRestrictions = _billingTokenRestrictions[token];
        if (keccak256(abi.encode(restrictions)) == keccak256(abi.encode(oldRestrictions))) {
            revert BillingTokenRestrictionsNotChanged();
        }

        bool exists = _billingTokenRestrictions[token].maxMaintenanceFeePerDay > 0;
        bool existanceChanged = exists != (restrictions.maxMaintenanceFeePerDay > 0);
        if (existanceChanged) {
            if (restrictions.maxMaintenanceFeePerDay == 0) {
                // We're removing the token
                address[] memory newBillingTokens = new address[](_billingTokens.length - 1);

                uint256 j = 0;
                for (uint256 i = 0; i < _billingTokens.length; ++i) {
                    if (_billingTokens[i] != token) {
                        newBillingTokens[j] = _billingTokens[i];
                        ++j;
                    }
                }

                _billingTokens = newBillingTokens;
            } else {
                // We're adding the token
                _billingTokens.push(token);
            }
        }

        _billingTokenRestrictions[token] = restrictions;

        emit BillingTokenRestrictionsUpdated(token, oldRestrictions, restrictions, block.timestamp);
    }

    function _setGasPriceOracleValidity(address oracle, bool isValid) internal virtual {
        if (_gasOracleWhitelist[oracle] == isValid) {
            revert GasPriceOracleValidityNotChanged();
        }

        if (isValid) {
            // We're adding the oracle
            _gasPriceOracles.push(oracle);
        } else {
            // We're removing the oracle
            address[] memory newGasPriceOracles = new address[](_gasPriceOracles.length - 1);

            uint256 j = 0;
            for (uint256 i = 0; i < _gasPriceOracles.length; ++i) {
                if (_gasPriceOracles[i] != oracle) {
                    newGasPriceOracles[j] = _gasPriceOracles[i];
                    ++j;
                }
            }

            _gasPriceOracles = newGasPriceOracles;
        }

        _gasOracleWhitelist[oracle] = isValid;

        emit GasPriceOracleValidityUpdated(oracle, isValid, block.timestamp);
    }

    function _setL1GasCalculatorValidity(address calculator, bool isValid) internal virtual {
        if (_l1GasCalculatorWhitelist[calculator] == isValid) {
            revert L1GasCalculatorValidityNoChanged();
        }

        if (isValid) {
            // We're adding the calculator
            _l1GasCalculators.push(calculator);
        } else {
            // We're removing the calculator
            address[] memory newL1GasCalculators = new address[](_l1GasCalculators.length - 1);

            uint256 j = 0;
            for (uint256 i = 0; i < _l1GasCalculators.length; ++i) {
                if (_l1GasCalculators[i] != calculator) {
                    newL1GasCalculators[j] = _l1GasCalculators[i];
                    ++j;
                }
            }

            _l1GasCalculators = newL1GasCalculators;
        }

        _l1GasCalculatorWhitelist[calculator] = isValid;

        emit L1GasCalculatorValidityUpdated(calculator, isValid, block.timestamp);
    }

    /******************************************************************************************************************
     * AUTHORIZATION
     *****************************************************************************************************************/

    function _authSetFeeConfig() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authSetRegistryRestrictions() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authSetRegistryBillingRestrictions() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authSetBillingTokenRestrictions() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authSetGasPriceOracleValidity() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authCreateRegistry() internal view virtual onlyRoleOrOpenRole(Roles.FACTORY_REGISTRY_DEPLOYER) {}

    function _authSetProtocolAdmin() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authWithdrawErc20() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}

    function _authWithdrawNative() internal view virtual onlyRole(Roles.PROTOCOL_ADMIN) {}
}
