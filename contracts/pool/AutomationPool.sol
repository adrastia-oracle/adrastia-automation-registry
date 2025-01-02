// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AutomationPoolBase} from "./AutomationPoolBase.sol";
import {IAutomationPoolMinimal} from "./IAutomationPoolMinimal.sol";
import {IPoolExecutor} from "./IPoolExecutor.sol";
import {IAutomationRegistry} from "../registry/IAutomationRegistry.sol";
import {AutomationCompatibleInterface} from "../interfaces/AutomationCompatibleInterface.sol";
import {Roles} from "../access/Roles.sol";
import {IDiamondLoupe} from "../diamond/interfaces/IDiamondLoupe.sol";
import {IL1GasCalculator} from "../gas/IL1GasCalculator.sol";

contract AutomationPool is IAutomationPoolMinimal, Initializable, AutomationPoolBase {
    using SafeERC20 for IERC20;

    /******************************************************************************************************************
     * INITIALIZER
     *****************************************************************************************************************/

    function initialize(address registry_, uint256 id_, address admin, address diamond_) public virtual initializer {
        __AccessControlEnumerable_init();

        if (registry_ == address(0)) {
            revert InvalidRegistry(registry_);
        }
        if (admin == address(0)) {
            revert InvalidAdmin(admin);
        }

        _poolState1 = PoolState1({activeBatchCount: 0, flags: 0, status: PoolStatus.OPEN, registry: registry_});

        id = id_;
        diamond = diamond_;

        _initializeRoles(admin);
        _initializeExecutor(registry_);
    }

    function _initializeRoles(address admin) internal virtual {
        // POOL_ADMIN manages itself
        _setRoleAdmin(Roles.POOL_ADMIN, Roles.POOL_ADMIN);
        // POOL_ADMIN manages POOL_MANAGER
        _setRoleAdmin(Roles.POOL_MANAGER, Roles.POOL_ADMIN);
        // POOL_MANAGER manages POOL_WORK_MANAGER
        _setRoleAdmin(Roles.POOL_WORK_MANAGER, Roles.POOL_MANAGER);

        // Grant all management roles to the admin
        _grantRole(Roles.POOL_ADMIN, admin);
        _grantRole(Roles.POOL_MANAGER, admin);
        _grantRole(Roles.POOL_WORK_MANAGER, admin);
    }

    function _initializeExecutor(address registry_) internal virtual {
        address executorBeacon = IAutomationRegistry(registry_).executorBeacon();

        bytes memory data = abi.encodeWithSignature("initialize(address)", address(this));
        BeaconProxy executorProxy = new BeaconProxy(executorBeacon, hex"");

        (bool success, ) = address(executorProxy).call(data);
        if (!success) {
            revert FailedToInitializeExecutor();
        }

        executor = address(executorProxy);
    }

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    receive() external payable {
        // Use only depositGasFunds to deposit funds
        revert();
    }

    fallback() external payable {
        address facet = IDiamondLoupe(diamond).facetAddress(bytes4(msg.sig));
        if (facet == address(0)) {
            revert("AutomationPool: Function does not exist"); // TODO: Custom revert
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

    function registry() external view virtual override returns (address) {
        return _poolState1.registry;
    }

    function isBatchActive(bytes32 batchId) external view virtual override returns (bool) {
        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN && status != PoolStatus.NOTICE) {
            // Pool is closing or closed
            return false;
        }

        WorkExecutionParams memory execParams = _executionParams[batchId];

        return execParams.maxGasLimit != 0;
    }

    event Debug(string message);

    function checkWork(
        bytes32 batchId,
        uint256 flags, // Currently unused. Reserved for future use.
        OffchainDataProvision calldata offchainData
    )
        external
        virtual
        override
        nonReentrant
        whenOpen
        whenNotInDebt
        returns (
            uint256 workRequiredCount,
            WorkDefinition memory workDefinition,
            CheckedWorkItem[] memory checkedWorkItems
        )
    {
        _authCheckWork();

        flags; // Silence unused variable warning

        // Fetch check and execution params
        WorkCheckParams memory checkParams = _checkParams[batchId];
        WorkExecutionParams memory execParams = _executionParams[batchId];

        // Check restrictions
        (uint256 checkGasLimit, ) = _checkCheckExecutionRestrictions(
            _poolState1.registry,
            batchId,
            checkParams,
            execParams
        );
        if (checkParams.maxGasLimit < checkGasLimit) {
            // The check gas limit is lower than the pool's restrictions. Let's use the lower limit.
            checkGasLimit = checkParams.maxGasLimit;
        }

        uint256 workLength = checkParams.workItems.length;

        OffchainCheckDataHandling dataHandling = checkParams.offchainCheckDataHandling;

        {
            uint256 offchainDataLen = offchainData.itemsData.length;
            if (dataHandling != OffchainCheckDataHandling.IGNORE && offchainDataLen != workLength) {
                // We're expected to handle offchain data, but the amount does not match the work items. Revert.
                revert("OffchainDataMismatch"); // TODO: Custom revert
            }
        }

        // Create call array
        IPoolExecutor.Call[] memory calls = new IPoolExecutor.Call[](workLength);
        bytes[] memory triggers = new bytes[](workLength);

        // Populate call array with onchain work
        for (uint256 i = 0; i < workLength; ++i) {
            // Encode the call
            WorkItem memory workItem = checkParams.workItems[i];
            bytes memory checkData = workItem.checkData;

            // Handle the provided offchain data only if the option is not nil or ignore
            if (dataHandling != OffchainCheckDataHandling.IGNORE) {
                // We may have some offchain data to add. Let's do a hash check to ensure the data matches the trigger.
                if (keccak256(checkData) == offchainData.itemsData[i].triggerHash) {
                    // The data is valid. Let's do something with it.

                    if (dataHandling == OffchainCheckDataHandling.PREPEND) {
                        checkData = abi.encodePacked(offchainData.itemsData[i].data, checkData);
                    } else if (dataHandling == OffchainCheckDataHandling.APPEND) {
                        checkData = abi.encodePacked(checkData, offchainData.itemsData[i].data);
                    } else if (dataHandling == OffchainCheckDataHandling.REPLACE) {
                        checkData = offchainData.itemsData[i].data;
                    } else {
                        // Invalid data handling. Revert.
                        revert("InvalidDataHandling"); // TODO: Custom revert
                    }
                } else {
                    // The provided data does not match the trigger. Revert.
                    revert("OffchainDataMismatch"); // TODO: Custom revert
                }
            }

            bytes memory call = bytes.concat(checkParams.selector, checkData);

            // Note that the value is zero here. The value is only used in performWork.
            calls[i] = IPoolExecutor.Call(true, workItem.checkGasLimit, 0, call);
            triggers[i] = checkData;
        }

        // Perform multicall
        IPoolExecutor.Result[] memory results = IPoolExecutor(executor).aggregateCalls{gas: checkGasLimit}(
            checkParams.target,
            calls
        );

        // Extract results
        checkedWorkItems = new CheckedWorkItem[](workLength);
        workRequiredCount = 0;
        for (uint256 i = 0; i < workLength; ++i) {
            bool needsWork = false;
            bytes memory workData = hex"";

            if (checkParams.callResultInterpretation == CheckWorkCallResultInterpretation.SUCCESS) {
                needsWork = results[i].success;
                workData = results[i].returnData;
            } else if (checkParams.callResultInterpretation == CheckWorkCallResultInterpretation.FAILURE) {
                needsWork = !results[i].success;
                workData = results[i].returnData;
            } else if (checkParams.callResultInterpretation == CheckWorkCallResultInterpretation.ACI) {
                if (results[i].success) {
                    // Decode the result
                    needsWork = abi.decode(results[i].returnData, (bool));
                }
            } else if (checkParams.callResultInterpretation == CheckWorkCallResultInterpretation.CONDITIONAL) {
                if (results[i].success) {
                    needsWork = _checkCondition(results[i].returnData, checkParams.workItems[i].condition);
                    workData = results[i].returnData;
                }
            } else {
                // Invalid option. Revert.
                revert("InvalidCallResultInterpretation"); // TODO: Custom revert
            }

            if (needsWork) {
                ++workRequiredCount;
                // We need work. Now let's check if we need to change the work data.
                if (checkParams.executionDataHandling == ExecutionDataHandling.NONE) {
                    workData = hex""; // Always no data
                } else if (checkParams.executionDataHandling == ExecutionDataHandling.CHECK_RESULT_DATA_ONLY) {
                    // We use the result from the check call as the perform data. No need to change it.
                    // Note that this data depends on the check result interpretation.
                } else if (checkParams.executionDataHandling == ExecutionDataHandling.EXECUTION_DATA_ONLY) {
                    // We use workItem.performData as the perform data
                    workData = checkParams.workItems[i].executionData;
                } else if (checkParams.executionDataHandling == ExecutionDataHandling.CHECK_DATA_ONLY) {
                    workData = triggers[i];
                } else if (checkParams.executionDataHandling == ExecutionDataHandling.RAW_CHECK_DATA_ONLY) {
                    workData = checkParams.workItems[i].checkData;
                } else if (checkParams.executionDataHandling == ExecutionDataHandling.ACI) {
                    if (results[i].success) {
                        // Decode the result
                        (, workData) = abi.decode(results[i].returnData, (bool, bytes));

                        // Since in performWork, we concat the selector with the work data, we need to encode it here.
                        workData = abi.encode(workData);
                    } else {
                        // The call failed so we're unable to get the data. This can happen if the call result
                        // interpretation is set to something weird.
                        revert("ACIFailed"); // TODO: Custom revert
                    }
                } else {
                    // Invalid option. Revert.
                    revert("InvalidPerformDataHandling"); // TODO: Custom revert
                }
            }

            checkedWorkItems[i] = CheckedWorkItem({
                index: i,
                itemHash: keccak256(abi.encode(checkParams.workItems[i])),
                needsExecution: needsWork,
                callWasSuccessful: results[i].success,
                checkCallData: triggers[i],
                checkCallResult: results[i].returnData,
                executionData: workData
            });
        }

        workDefinition = WorkDefinition({checkParams: checkParams, executionParams: execParams});
    }

    struct PerformWorkGasData {
        uint256 gasStart;
        uint256 gasUsed;
        uint256 gasCompensationWithoutPremium;
        uint256 totalGasCompensation;
        uint256 gasPrice;
        uint256 gasOverhead;
        uint16 registryFee;
        address l1GasCalculator;
        uint256 gasPremiumBasisPoints;
        uint16 protocolFee;
        uint256 debtToProtocol;
        uint256 debtToRegistry;
        uint256 debtToWorker;
    }

    // Gas: Overhead is estimated to be about 153k gas. Gas measurement accounts for most of this, with the following
    // not included:
    //  - Reentrancy check: ~5k gas
    //  - BatchExecution log: ~4k gas
    //  - Registry callback: ~19k gas
    //  - Load ID at the end: ~2k gas
    //    - Total: ~30k gas
    function performWork(
        bytes32 batchId,
        uint256 workerFlags, // Currently unused. Reserved for future use.
        PerformWorkItem[] calldata workData,
        IPoolExecutor.Call[] calldata calls
    ) external virtual override nonReentrant /* ~5k gas */ {
        PerformWorkGasData memory gasData;

        gasData.gasStart = gasleft();

        uint256 poolBalance = address(this).balance;
        if (poolBalance == 0) {
            // This should only ever occur if this tx is quickly following another performWork tx that consumed all the
            // funds. We revert to prevent the worker from wasting gas without compensation.
            // The worker has already wasted gas for the calldata and initial call, but we don't want them to waste more.
            // While we support gas debt, it's not 100% that we'll be paid back, so we place this restriction to prevent
            // workers from wasting more gas.
            // Registries can enforce a higher minimum balance and lower exec gas limit to prevent this.
            revert InsufficientGasFunds(0, 0);
        }

        PoolState1 memory poolState1 = _poolState1;
        {
            // Gas-efficient status check to ensure that the pool is not closed.
            PoolStatus status = poolState1.status;
            if (status == PoolStatus.CLOSING) {
                // Might be closed. Let's check if it's past the closing time.
                BillingState memory billing = _billingState;

                uint256 closeTime = billing.closeStartTime + billing.closingPeriod;

                if (block.timestamp >= closeTime) {
                    status = PoolStatus.CLOSED;
                }
            }

            if (status == PoolStatus.CLOSED) {
                // Nothing should get through here. The pool is closed.
                revert PoolIsClosed();
            }
        }

        workerFlags; // Silence unused variable warning

        address registry_ = poolState1.registry;

        _authPerformWork(registry_); // ~14k gas

        if (workData.length == 0) {
            // No work to perform. Can only be caused by a worker error, so we revert.
            revert("NoWork"); // TODO: Custom revert
        }

        if (calls.length != workData.length) {
            // Mismatch in work data and calls. Can only be caused by a worker error, so we revert.
            revert("MismatchedWorkData"); // TODO: Custom revert
        }

        if (batchId == bytes32(0)) {
            // Invalid batch ID. Can only be caused by a worker error, so we revert.
            revert("InvalidBatchId"); // TODO: Custom revert
        }

        // Account for the initial gas for the call
        gasData.gasStart += _estimateInitialGas();

        WorkExecutionParams memory execParams = _executionParams[batchId];

        // Load gas data
        (
            gasData.gasPrice,
            gasData.gasOverhead,
            gasData.registryFee,
            gasData.l1GasCalculator,
            gasData.gasPremiumBasisPoints,
            gasData.protocolFee
        ) = IAutomationRegistry(registry_).getGasData(); // ~25k gas

        // Check execution restrictions and get gas and fee info
        ExecutionError pError = _checkPerformExecutionRestrictions(execParams);

        // Declare vars to hold results
        bool success = false;
        uint256 numSuccess = 0;
        uint256 numFailures = 0;
        uint256 numSkipped = 0;

        {
            uint256 workLength = workData.length;

            // Count aggregate work items
            uint256 aggregateWorkItemCount = 0;
            for (uint256 i = 0; i < workLength; ++i) {
                aggregateWorkItemCount += workData[i].aggregateCount;
            }

            // Only proceed if there's not an error
            if (pError == ExecutionError.NONE) {
                if (
                    aggregateWorkItemCount >= execParams.minBatchSize &&
                    aggregateWorkItemCount <= execParams.maxBatchSize
                ) {
                    // Verify the call function matches the execution function
                    bytes4 expectedSelector = execParams.selector;
                    bool badCalls = false;
                    for (uint256 j = 0; j < workLength; ++j) {
                        bytes4 actualSelector;
                        bytes calldata callData = calls[j].callData;
                        if (callData.length < 4) {
                            // Invalid call data. Can only be caused by a worker error, so we revert.
                            revert("InvalidCallData"); // TODO: Custom revert
                        }
                        assembly {
                            // Load the selector (first 4 bytes) from callData in calldata
                            let callDataOffset := callData.offset
                            calldatacopy(0x0, callDataOffset, 4) // Copy 4 bytes to memory at address 0x0
                            actualSelector := mload(0x0) // Load those 4 bytes into actualSelector
                        }

                        if (actualSelector != expectedSelector) {
                            // The selector does not match the expected selector. This can happen if the manager
                            // changes the function after the worker has checked the work. We skip all work.
                            badCalls = true;

                            break;
                        }
                    }

                    if (!badCalls) {
                        // Create results array
                        IPoolExecutor.Result[] memory results;

                        // Execute the work
                        try
                            IPoolExecutor(executor).aggregateCalls{gas: execParams.maxGasLimit}(
                                execParams.target,
                                calls
                            )
                        returns (IPoolExecutor.Result[] memory _results) {
                            results = _results;
                            success = true;
                        } catch {
                            // Failed to perform work
                        }

                        if (success) {
                            // Check results
                            for (uint256 i = 0; i < workLength; ++i) {
                                uint256 aggregateCount = workData[i].aggregateCount;

                                if (results[i].success) {
                                    numSuccess += aggregateCount;

                                    emit WorkItemExecution(
                                        batchId,
                                        execParams.target,
                                        msg.sender,
                                        aggregateCount,
                                        Result.SUCCESS,
                                        workData[i].trigger,
                                        results[i].gasUsed,
                                        block.timestamp
                                    ); // ~5k gas (can be more or less depending on trigger)
                                } else {
                                    numFailures += aggregateCount;

                                    emit WorkItemExecution(
                                        batchId,
                                        execParams.target,
                                        msg.sender,
                                        aggregateCount,
                                        Result.FAILURE,
                                        workData[i].trigger,
                                        results[i].gasUsed,
                                        block.timestamp
                                    );
                                }
                            }
                        } else {
                            // Executor reverted, skipping all work
                            numSkipped = aggregateWorkItemCount;
                        }
                    } else {
                        // Bad calls. Skipping all work
                        numSkipped = aggregateWorkItemCount;
                    }
                } else {
                    // Skipping all work
                    numSkipped = aggregateWorkItemCount;
                }
            } else {
                // Skipping all work
                numSkipped = aggregateWorkItemCount;

                emit ExecutionRestricted(batchId, pError, block.timestamp);
            }
        }

        // Calculate gas compensation
        {
            uint256 l1GasFee = 0;
            if (gasData.l1GasCalculator != address(0)) {
                l1GasFee = IL1GasCalculator(gasData.l1GasCalculator).calculateL1GasFee(msg.data.length);
            }

            gasData.gasUsed = (gasData.gasStart - gasleft()) + gasData.gasOverhead;

            gasData.gasCompensationWithoutPremium = ((gasData.gasUsed * gasData.gasPrice) + l1GasFee);
            gasData.totalGasCompensation =
                (gasData.gasCompensationWithoutPremium * (10000 + gasData.gasPremiumBasisPoints)) /
                10000;
        }

        // If the balance is insufficient, we consume the remaining balance and record the debt.
        // This is to prevent the worker from wasting gas without compensation.
        if (poolBalance < gasData.totalGasCompensation) {
            uint256 debt = gasData.totalGasCompensation - poolBalance;

            // Recalculate gas compensation using the remaining balance
            gasData.totalGasCompensation = poolBalance;
            gasData.gasCompensationWithoutPremium =
                (gasData.totalGasCompensation * 10000) /
                (10000 + gasData.gasPremiumBasisPoints);

            // Calculate the gas preium portion of the debt
            uint256 debtWithoutPremium = (debt * 10000) / (10000 + gasData.gasPremiumBasisPoints);
            uint256 premiumDebt = debt - debtWithoutPremium;

            // Calculate who the debt is owed to
            // Note: Fees to registry and protocol are intentionally rounded down, in favor of workers
            gasData.debtToProtocol = (premiumDebt * gasData.protocolFee) / 10000;
            gasData.debtToRegistry = ((premiumDebt - gasData.debtToProtocol) * gasData.registryFee) / 10000;
            gasData.debtToWorker = debt - gasData.debtToProtocol - gasData.debtToRegistry;

            uint256 oldTotalGasDebt = _totalGasDebt;

            _addGasDebt(msg.sender, gasData.debtToProtocol, gasData.debtToRegistry, gasData.debtToWorker);

            emit GasDebtUpdated(msg.sender, GasDebtChange.INCREASE, debt, oldTotalGasDebt + debt, block.timestamp);
        }

        // Calculate the amount of gas compensation that the registry collects
        // Note: Fees to registry and protocol are intentionally rounded down, in favor of workers
        uint256 feeToProtocol;
        uint256 feeToRegistry;
        uint256 feeToWorker;
        {
            uint256 totalPremium = gasData.totalGasCompensation - gasData.gasCompensationWithoutPremium;
            feeToProtocol = (totalPremium * gasData.protocolFee) / 10000;
            feeToRegistry = ((totalPremium - feeToProtocol) * gasData.registryFee) / 10000;
            feeToWorker = gasData.totalGasCompensation - feeToProtocol - feeToRegistry;
        }

        if (feeToWorker > 0) {
            (bool sentToWorker, ) = payable(msg.sender).call{value: feeToWorker}("");
            if (!sentToWorker) {
                // Failed to compensate the worker.
                revert FailedToCompensateWorker(msg.sender, feeToWorker);
            }
        }

        emit BatchExecution(
            batchId,
            execParams.target,
            msg.sender,
            success ? Result.SUCCESS : Result.FAILURE,
            numSuccess,
            numFailures,
            numSkipped,
            gasData.gasUsed,
            gasData.totalGasCompensation,
            gasData.debtToProtocol + gasData.debtToRegistry + gasData.debtToWorker,
            block.timestamp
        ); // ~4k gas

        // Inform the registry about the work performed
        IAutomationRegistry(registry_).poolWorkPerformedCallback{value: feeToProtocol + feeToRegistry}(
            id,
            msg.sender,
            gasData.gasUsed,
            feeToWorker,
            feeToRegistry,
            feeToProtocol,
            gasData.debtToWorker,
            gasData.debtToRegistry,
            gasData.debtToProtocol
        ); // ~19k gas
    }

    function depositGasFunds() external payable virtual override nonReentrant {
        if (msg.value == 0) {
            // No funds to deposit
            revert CannotDepositNothing();
        }

        emit GasFundsMoved(msg.sender, address(this), GasFundMovement.DEPOSIT, msg.value, block.timestamp);

        uint256 oldTotalGasDebt = _totalGasDebt;
        if (oldTotalGasDebt > 0) {
            // Pay off debt
            uint256 poolBalance = address(this).balance;
            if (poolBalance >= oldTotalGasDebt) {
                // Paying off in full

                uint256 totalWorkerDebt = 0;

                // Pay off worker debts
                GasDebtToWorker[] memory workerDebts = _gasDebt.workerDebts;
                uint256 workerDebtsLen = workerDebts.length;
                for (uint256 i = 0; i < workerDebtsLen; ++i) {
                    uint256 workerDebt = workerDebts[i].debt;
                    totalWorkerDebt += workerDebt;

                    (bool success, ) = payable(workerDebts[i].worker).call{value: workerDebt}("");
                    if (!success) {
                        // Failed to compensate the worker.
                        revert FailedToCompensateWorker(workerDebts[i].worker, workerDebt);
                    }
                }

                uint256 debtToProtocol = _gasDebt.protocolDebt;
                uint256 debtToRegistry = _gasDebt.registryDebt;

                // Pay off registry debt and inform the registry
                IAutomationRegistry(_poolState1.registry).poolGasDebtRecovered{value: debtToProtocol + debtToRegistry}(
                    id,
                    debtToProtocol,
                    debtToRegistry,
                    totalWorkerDebt
                );

                // Update debt records
                _totalGasDebt = 0;
                _gasDebt.protocolDebt = 0;
                _gasDebt.registryDebt = 0;
                _gasDebt.workerDebts = new GasDebtToWorker[](0);

                emit GasDebtUpdated(msg.sender, GasDebtChange.DECREASE, oldTotalGasDebt, 0, block.timestamp);
            } else {
                // Not enough funds to pay off the debt in full. Revert.
                uint256 shortfall = oldTotalGasDebt - poolBalance;

                revert DebtMustBePaidInFull(oldTotalGasDebt, shortfall);
            }
        }
    }

    function withdrawGasFunds(address to, uint256 amount) external virtual override nonReentrant whenNotInDebt {
        _authWithdrawGasFunds();

        if (getPoolStatus() != PoolStatus.CLOSED) {
            // Pool is not closed, so restrictions apply

            PoolState1 memory poolState1 = _poolState1;

            // Enforce minimum balance
            uint256 balance = address(this).balance;
            uint256 balanceAfter = balance - amount;
            (, , uint96 minBalancePerBatch) = IAutomationRegistry(poolState1.registry).getPoolRestrictions();
            uint256 minBalance = uint256(minBalancePerBatch) * poolState1.activeBatchCount;
            if (balanceAfter < minBalance) {
                revert MinimumBalanceRestriction(minBalance);
            }

            // TODO: Enforce a batch unregistration delay before allowing withdrawal
        }

        if (amount > 0) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) {
                revert FailedToWithdrawGasFunds(amount);
            }

            emit GasFundsMoved(msg.sender, to, GasFundMovement.WITHDRAW, amount, block.timestamp);
        } else {
            // No funds to withdraw
            revert FailedToWithdrawGasFunds(amount);
        }
    }

    function withdrawErc20(
        address token,
        address to,
        uint256 amount
    ) external virtual override nonReentrant whenNotInDebt {
        _authWithdrawErc20();

        IERC20(token).safeTransfer(to, amount);

        emit Erc20Withdrawn(msg.sender, token, to, amount, block.timestamp);
    }

    function closePool() external virtual override nonReentrant {
        _authClosePool();

        PoolStatus status = getPoolStatus();
        if (status == PoolStatus.CLOSING || status == PoolStatus.CLOSED) {
            revert PoolAlreadyClosed();
        }

        // Start closing the pool
        _billingState.closeStartTime = uint32(block.timestamp);
        _poolState1.status = PoolStatus.CLOSING;

        address registry_ = _poolState1.registry;

        IAutomationRegistry(registry_).poolClosedCallback(id);

        // TODO: More info?
        emit PoolClosed(
            msg.sender == registry_ ? CloseReason.ADMINISTRATIVE : CloseReason.USER_REQUEST,
            block.timestamp
        );
    }

    function getPoolType() external view virtual override returns (uint16) {
        return IAutomationRegistry(_poolState1.registry).poolType();
    }

    function getTotalGasDebt() external view virtual override returns (uint256) {
        return _totalGasDebt;
    }

    function name() external view virtual returns (string memory) {
        return _metadata.name;
    }

    function description() external view virtual returns (string memory) {
        return _metadata.description;
    }

    function setMetadata(PoolMetadata calldata metadata) external virtual {
        _authSetMetadata();

        _setMetadata(metadata);
    }

    function calculateMinimumGasFundsRequired() external view virtual returns (uint256) {
        PoolStatus status = getPoolStatus();
        if (status == PoolStatus.CLOSED) {
            // Pool is closed. No minimum gas funds required.
            return 0;
        }

        PoolState1 memory poolState1 = _poolState1;
        (, , uint96 minBalancePerBatch) = IAutomationRegistry(poolState1.registry).getPoolRestrictions();

        return uint256(minBalancePerBatch) * poolState1.activeBatchCount;
    }

    /******************************************************************************************************************
     * PUBLIC FUNCTIONS
     *****************************************************************************************************************/

    function getPoolStatus()
        public
        view
        virtual
        override(IAutomationPoolMinimal, AutomationPoolBase)
        returns (PoolStatus)
    {
        return AutomationPoolBase.getPoolStatus();
    }

    /******************************************************************************************************************
     * INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function _setMetadata(PoolMetadata calldata newMetadata) internal virtual {
        if (keccak256(abi.encode(_metadata)) == keccak256(abi.encode(newMetadata))) {
            revert("Metadata not changed"); // TODO: Custom revert
        }

        PoolMetadata memory oldMetadata = _metadata;

        _metadata = newMetadata;

        emit MetadataUpdated(oldMetadata, newMetadata, block.timestamp);
    }

    function _checkCondition(bytes memory returnData, bytes memory condition) internal virtual returns (bool) {
        uint256 condVersionAndOp = abi.decode(condition, (uint256));

        // The version is stored in the first 32 bits
        uint256 condVersion = condVersionAndOp >> 224;

        if (condVersion == 1) {
            // Simple conditions

            // Extract the operator which is stored in the second 16 bits (after the version)
            Operator operator = Operator((condVersionAndOp >> 208) & 0xFFFF);

            uint256 operandR;
            uint256 operandR2; // Used for 3-operand operators

            // Decode the operand from the condition
            if (operator == Operator.BTW) {
                // 3-operand operator
                (, operandR, operandR2) = abi.decode(condition, (uint256, uint256, uint256));
            } else {
                (, operandR) = abi.decode(condition, (uint256, uint256));
            }

            // Decode the return data
            uint256 operandL = abi.decode(returnData, (uint256));

            // Perform the comparison
            if (operator == Operator.EQ) {
                return operandL == operandR;
            } else if (operator == Operator.NE) {
                return operandL != operandR;
            } else if (operator == Operator.LT) {
                return operandL < operandR;
            } else if (operator == Operator.LTE) {
                return operandL <= operandR;
            } else if (operator == Operator.GT) {
                return operandL > operandR;
            } else if (operator == Operator.GTE) {
                return operandL >= operandR;
            } else if (operator == Operator.BTW) {
                return operandL >= operandR && operandL <= operandR2;
            } else {
                // Invalid operator
                revert("InvalidOperator"); // TODO: Custom revert
            }
        } else {
            // Invalid condition version
            revert("InvalidConditionVersion"); // TODO: Custom revert
        }
    }

    function _calculateTotalGasDebt() internal virtual returns (uint256, uint256) {
        uint256 totalDebt = 0;
        uint256 totalWorkerDebt = 0;

        // Load debt
        GasDebt memory gasDebt = _gasDebt;

        // Add protocol debt
        totalDebt += gasDebt.protocolDebt;
        // Add registry debt
        totalDebt += gasDebt.registryDebt;

        // Add worker debts
        GasDebtToWorker[] memory workerDebts = gasDebt.workerDebts;
        uint256 workerDebtsLen = workerDebts.length;

        for (uint256 i = 0; i < workerDebtsLen; ++i) {
            totalWorkerDebt += workerDebts[i].debt;
        }

        totalDebt += totalWorkerDebt;

        return (totalDebt, totalWorkerDebt);
    }

    function _addGasDebt(
        address worker,
        uint256 protocolDebt,
        uint256 registryDebt,
        uint256 workerDebt
    ) internal virtual {
        // Add registry debt, if any
        _gasDebt.protocolDebt += protocolDebt;
        _gasDebt.registryDebt += registryDebt;

        if (workerDebt > 0) {
            // Load existing worker debts, if any
            GasDebtToWorker[] memory workerDebts = _gasDebt.workerDebts;
            uint256 workerDebtsLen = workerDebts.length;

            uint256 workerIndex = 0;
            bool workerHasIndex = false;

            // Find the worker in the array, if it exists
            for (uint256 i = 0; i < workerDebtsLen; ++i) {
                if (workerDebts[i].worker == worker) {
                    workerIndex = i;
                    workerHasIndex = true;

                    break;
                }
            }

            if (workerHasIndex) {
                // Add to existing debt
                _gasDebt.workerDebts[workerIndex].debt += workerDebt;
            } else {
                // Add new debt
                GasDebtToWorker memory newDebt = GasDebtToWorker({worker: worker, debt: workerDebt});
                _gasDebt.workerDebts.push(newDebt);
            }
        }

        // Update total debt
        (_totalGasDebt, ) = _calculateTotalGasDebt();
    }

    function _estimateInitialGas() internal view virtual returns (uint256) {
        // We use simple calldata gas estimation as performing a more accurate estimation would be too expensive.
        return 21_000 + msg.data.length * 16; // 21k base gas + calldata gas
    }

    function _checkCheckExecutionRestrictions(
        address registry_,
        bytes32 batchId,
        WorkCheckParams memory checkParams,
        WorkExecutionParams memory execParams
    ) internal view virtual returns (uint256 checkGasLimit, uint256 executionGasLimit) {
        if (checkParams.source != CheckWorkSource.FUNCTION_CALL) {
            revert("Not function call"); // TODO: Custom revert
        }

        // Fetch pool restrictions.
        // Note: We discard restrictions on gas limits. This allows pools to continue operating even if the registry
        // changes the restrictions (restrictions are checked when changing work).
        uint256 minBalancePerBatch;
        (checkGasLimit, executionGasLimit, minBalancePerBatch) = IAutomationRegistry(registry_).getPoolRestrictions();
        uint256 minBalance = minBalancePerBatch * _poolState1.activeBatchCount;

        // Check the perform gas limit against the registry restriction.
        // Note that we don't check the check gas limit (we just use the lower of the two. If the call fails b/c of
        // this, there will be no wasted gas funds).
        if (execParams.maxGasLimit > executionGasLimit) {
            // The max perform gas limit exceeds the pool's restrictions.
            revert("MaxGasLimitExceedsRestrictions"); // TODO: Custom revert
        }

        uint256 poolBalance = address(this).balance;
        if (poolBalance < minBalance || poolBalance == 0) {
            // Balance not enough to perform work.
            // The purpose of this restriction is to prevent insufficient funds to compensate the worker. This check
            // isn't 100% effective, but it can be good enough.
            // Note: This restriction is not applied to performWork to reduce the consumption of gas.
            revert InsufficientGasFunds(minBalance, address(this).balance);
        }

        // Check gas price limitations
        (uint256 gasPrice, , , , , ) = IAutomationRegistry(registry_).getGasData();
        if (gasPrice > execParams.maxGasPrice) {
            // Gas price exceeds the limit.
            // The purpose of this restriction is to prevent the worker from spending more gas than the user desires.
            // Note: This restriction is not applied to performWork to mitigate an attack vector. Workers are expected
            // to ensure the max gas is applied when submitting the transaction.
            revert GasPriceExceedsLimit(batchId, gasPrice, execParams.maxGasPrice);
        }

        ExecutionError pError = _checkPerformExecutionRestrictions(execParams);
        if (pError == ExecutionError.NONE) {
            return (checkGasLimit, executionGasLimit);
        } else if (pError == ExecutionError.BATCH_NOT_FOUND) {
            revert BatchNotFound(batchId);
        } else if (pError == ExecutionError.BATCH_DISABLED) {
            revert BatchDisabled(batchId);
        } else {
            revert("Unknown error"); // TODO: Custom revert
        }
    }

    function _checkPerformExecutionRestrictions(
        WorkExecutionParams memory execParams
    ) internal view virtual returns (ExecutionError) {
        if (execParams.maxGasLimit == 0) {
            return ExecutionError.BATCH_NOT_FOUND;
        }

        if (execParams.flags & FLAG_ACTIVE == 0) {
            return ExecutionError.BATCH_DISABLED;
        }

        return ExecutionError.NONE;
    }

    /******************************************************************************************************************
     * AUTHORIZATION - REGISTRY WORKERS
     *****************************************************************************************************************/

    function _authCheckWork() internal view virtual {
        // Checking for work may alter state, so we need to have the same restrictions as performing work.
    }

    function _authPerformWork(address registry_) internal view virtual {
        if (msg.sender == address(0)) {
            // Off-chain call. Allow.
            return;
        }

        if (!IAccessControl(registry_).hasRole(Roles.WORKER, msg.sender)) {
            revert WorkerNotAuthorized(msg.sender);
        }
    }

    /******************************************************************************************************************
     * AUTHORIZATION - POOL MANAGER
     *****************************************************************************************************************/

    function _authWithdrawGasFunds() internal view virtual onlyRole(Roles.POOL_MANAGER) {}

    function _authWithdrawErc20() internal view virtual onlyRole(Roles.POOL_MANAGER) {}

    function _authSetMetadata() internal view virtual onlyRole(Roles.POOL_MANAGER) {}

    /**
     * @notice Authorizes the caller to close the pool. POOL_MANAGER and the registry can do this.
     */
    function _authClosePool() internal view virtual {
        bytes32 poolRole = Roles.POOL_MANAGER;

        if (!hasRole(poolRole, msg.sender)) {
            // Not a pool manager. Check if it's the registry.
            if (msg.sender != _poolState1.registry) {
                revert AccessControlUnauthorizedAccount(msg.sender, poolRole);
            }
        }
    }
}
