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

// TODO: ERC20 withdrawal event
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

        registry = registry_;
        id = id_;
        _status = PoolStatus.OPEN;
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

        // TODO: Ensure that we don't accept payment when calling non-payable functions
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

        // Fetch check and execution params
        WorkCheckParams memory checkParams = _checkParams[batchId];
        WorkExecutionParams memory execParams = _executionParams[batchId];

        // Check restrictions
        (uint256 checkGasLimit, ) = _checkCheckExecutionRestrictions(registry, batchId, checkParams, execParams);
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
                callCallResult: results[i].returnData,
                executionData: workData
            });
        }

        workDefinition = WorkDefinition({checkParams: checkParams, executionParams: execParams});
    }

    struct PerformWorkGasData {
        uint256 gasStart;
        uint256 gasUsed;
        uint256 gasCompensation;
        uint256 gasPrice;
        uint256 gasOverhead;
        uint16 registryFee;
        address l1GasCalculator;
        uint256 gasPremium;
    }

    function performWork(
        bytes32 batchId,
        uint256 flags, // Currently unused. Reserved for future use.
        PerformWorkItem[] calldata workData
    ) external virtual override nonReentrant whenNotClosed {
        // whenNotClosed is used to allow work to be closed up until the closing time, as a mechanism to prevent the
        // manager from causing the worker to waste gas.

        PerformWorkGasData memory gasData;

        gasData.gasStart = gasleft();

        _authPerformWork();

        if (workData.length == 0) {
            // No work to perform. Can only be caused by a worker error, so we revert.
            revert("NoWork"); // TODO: Custom revert
        }

        if (batchId == bytes32(0)) {
            // Invalid batch ID. Can only be caused by a worker error, so we revert.
            revert("InvalidBatchId"); // TODO: Custom revert
        }

        // Account for the initial gas for the call
        gasData.gasStart += _estimateInitialGas();

        WorkExecutionParams memory execParams = _executionParams[batchId];

        address registry_ = registry;

        // Load gas data
        (
            gasData.gasPrice,
            gasData.gasOverhead,
            gasData.registryFee,
            gasData.l1GasCalculator,
            gasData.gasPremium
        ) = IAutomationRegistry(registry_).getGasData();

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
                if (workLength >= execParams.minBatchSize && workLength <= execParams.maxBatchSize) {
                    // Create call array
                    IPoolExecutor.Call[] memory calls = new IPoolExecutor.Call[](workLength);

                    // Populate call array
                    for (uint256 i = 0; i < workLength; ++i) {
                        PerformWorkItem memory workItem = workData[i];
                        bytes memory call = bytes.concat(execParams.selector, workItem.executionData);

                        calls[i] = IPoolExecutor.Call(true, workItem.maxGasLimit, workItem.value, call);
                    }

                    // Create results array
                    IPoolExecutor.Result[] memory results;

                    // Execute the work
                    try
                        IPoolExecutor(executor).aggregateCalls{gas: execParams.maxGasLimit}(execParams.target, calls)
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
                                );
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

            gasData.gasUsed = gasData.gasStart - gasleft();

            gasData.gasCompensation =
                ((((gasData.gasUsed + gasData.gasOverhead) * gasData.gasPrice) + l1GasFee) *
                    (100 + gasData.gasPremium)) /
                100;
        }

        // If the balance is insufficient, we consume the remaining balance and record the debt.
        // This is to prevent the worker from wasting gas without compensation.
        uint256 registryDebt = 0;
        uint256 workerDebt = 0;
        {
            uint256 poolBalance = address(this).balance;
            uint256 debt = 0;

            if (poolBalance < gasData.gasCompensation) {
                debt = gasData.gasCompensation - poolBalance;
                gasData.gasCompensation = poolBalance;
            }

            if (debt > 0) {
                registryDebt = (debt * gasData.registryFee) / 10000;
                workerDebt = debt - registryDebt;

                uint256 oldTotalGasDebt = _totalGasDebt;

                _addGasDebt(msg.sender, registryDebt, workerDebt);

                emit GasDebtUpdated(msg.sender, GasDebtChange.INCREASE, debt, oldTotalGasDebt + debt, block.timestamp);
            }
        }

        // Calculate the amount of gas compensation that the registry collects, rounding down
        uint256 gasToRegistry = (gasData.gasCompensation * gasData.registryFee) / 10000;
        uint256 gasToWorker = gasData.gasCompensation - gasToRegistry;

        if (gasToWorker > 0) {
            (bool sentToWorker, ) = payable(msg.sender).call{value: gasToWorker}("");
            if (!sentToWorker) {
                // Failed to compensate the worker.
                revert FailedToCompensateWorker(msg.sender, gasToWorker);
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
            gasData.gasCompensation,
            registryDebt + workerDebt,
            block.timestamp
        );

        // Inform the registry about the work performed
        IAutomationRegistry(registry_).poolWorkPerformedCallback{value: gasToRegistry}(
            id,
            msg.sender,
            gasData.gasUsed,
            gasToWorker,
            gasToRegistry,
            workerDebt,
            registryDebt
        );
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

                // Calculate total worker debt
                (, uint256 totalWorkerDebt) = _calculateTotalGasDebt();

                // Pay off worker debts
                GasDebtToWorker[] memory workerDebts = _gasDebt.workerDebts;
                uint256 workerDebtsLen = workerDebts.length;
                for (uint256 i = 0; i < workerDebtsLen; ++i) {
                    uint256 workerDebt = workerDebts[i].debt;

                    (bool success, ) = payable(workerDebts[i].worker).call{value: workerDebt}("");
                    if (!success) {
                        // Failed to compensate the worker.
                        revert FailedToCompensateWorker(workerDebts[i].worker, workerDebt);
                    }
                }

                uint256 registryDebt = oldTotalGasDebt - totalWorkerDebt;

                // Pay off registry debt and inform the registry
                IAutomationRegistry(registry).poolGasDebtRecovered{value: registryDebt}(
                    id,
                    registryDebt,
                    totalWorkerDebt
                );

                // Update debt records
                _totalGasDebt = 0;
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

            // Enforce minimum balance
            uint256 balance = address(this).balance;
            uint256 balanceAfter = balance - amount;
            (, , uint96 minBalance) = IAutomationRegistry(registry).poolRestrictions();
            if (balanceAfter < minBalance) {
                revert MinimumBalanceRestriction(minBalance);
            }
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
        _status = PoolStatus.CLOSING;

        IAutomationRegistry(registry).poolClosedCallback(id);

        emit PoolClosed(
            msg.sender == registry ? CloseReason.ADMINISTRATIVE : CloseReason.USER_REQUEST,
            block.timestamp
        );
    }

    function getPoolType() external view virtual override returns (uint16) {
        return IAutomationRegistry(registry).poolType();
    }

    function getTotalGasDebt() external view virtual override returns (uint256) {
        return _totalGasDebt;
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

    function _checkCondition(bytes memory returnData, bytes memory condition) internal virtual returns (bool) {
        uint256 condVersionAndOp = abi.decode(condition, (uint256));

        // The version is stored in the first 32 bits
        uint256 condVersion = condVersionAndOp >> 224;

        if (condVersion == 1) {
            // Simple conditions

            // Extract the operator which is stored in the second 16 bits (after the version)
            Operator operator = Operator((condVersionAndOp >> 208) & 0xFFFF);

            // Decode the operand from the condition
            (, uint256 operandR) = abi.decode(condition, (uint256, uint256));

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

    function _addGasDebt(address worker, uint256 registryDebt, uint256 workerDebt) internal virtual {
        // Add registry debt, if any
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
        uint256 minBalance;
        (checkGasLimit, executionGasLimit, minBalance) = IAutomationRegistry(registry_).poolRestrictions();

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
        (uint256 gasPrice, , , , ) = IAutomationRegistry(registry_).getGasData();
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

    function _authPerformWork() internal view virtual {
        if (msg.sender == address(0)) {
            // Off-chain call. Allow.
            return;
        }

        if (!IAccessControl(registry).hasRole(Roles.WORKER, msg.sender)) {
            revert WorkerNotAuthorized(msg.sender);
        }
    }

    /******************************************************************************************************************
     * AUTHORIZATION - POOL MANAGER
     *****************************************************************************************************************/

    function _authWithdrawGasFunds() internal view virtual onlyRole(Roles.POOL_MANAGER) {}

    function _authWithdrawErc20() internal view virtual onlyRole(Roles.POOL_MANAGER) {}

    /**
     * @notice Authorizes the caller to close the pool. POOL_MANAGER and the registry can do this.
     */
    function _authClosePool() internal view virtual {
        bytes32 poolRole = Roles.POOL_MANAGER;

        if (!hasRole(poolRole, msg.sender)) {
            // Not a pool manager. Check if it's the registry.
            if (msg.sender != registry) {
                revert AccessControlUnauthorizedAccount(msg.sender, poolRole);
            }
        }
    }
}
