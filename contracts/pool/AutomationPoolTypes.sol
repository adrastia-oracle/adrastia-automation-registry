// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface AutomationPoolTypes {
    // TODO: Split billing state and billing terms
    struct BillingState {
        // SLOT 1: 256 bits
        uint32 lastBillingTime;
        uint32 nextBillingTime;
        uint32 paidBatchCapacity;
        uint32 nextBatchCapacity;
        uint32 closeStartTime;
        uint96 lastMaintenanceFee;
        // SLOT 2: 224 bits
        address lastBillingToken;
        uint32 gracePeriod;
        uint32 closingPeriod;
    }

    struct GasDebtToWorker {
        address worker;
        uint256 debt;
    }

    struct GasDebt {
        uint256 registryDebt;
        GasDebtToWorker[] workerDebts;
    }

    struct WorkItem {
        uint64 checkGasLimit;
        uint64 executionGasLimit;
        uint128 value;
        bytes condition;
        bytes checkData;
        bytes executionData;
    }

    struct OffchainWorkItemData {
        bytes32 triggerHash;
        bytes data;
    }

    struct OffchainDataProvision {
        OffchainWorkItemData[] itemsData;
    }

    struct CheckedWorkItem {
        /**
         * @notice The index of the work item in the batch.
         */
        uint256 index;

        /**
         * @notice The hash of the work item.
         */
        bytes32 itemHash;

        /**
         * @notice Whether the work item needs to be executed.
         */
        bool needsExecution;

        /**
         * @notice Whether the check call was successful.
         */
        bool callWasSuccessful;

        /**
         * @notice The calldata sent to the target contract.
         */
        bytes checkCallData;

        /**
         * @notice The result of the check call.
         */
        bytes callCallResult;

        /**
         * @notice The data to be sent to the target contract.
         */
        bytes executionData;
    }

    struct PerformWorkItem {
        /**
         * @notice The maximum gas limit for the executor call.
         */
        uint64 maxGasLimit;
        /**
         * @notice The call value in wei, sent from the executor to the target contract.
         */
        uint128 value;
        /**
         * @notice The index of the work item in the batch.
         */
        uint256 index;
        /**
         * @notice The hash of the work item.
         */
        bytes32 itemHash;
        /**
         * @notice Describes the work being performed. Only used for logging purposes.
         */
        bytes trigger;
        /**
         * @notice The data to be sent to the target contract.
         */
        bytes executionData;
    }

    struct WorkCheckParams {
        // Slot 1: 220 bits
        address target;
        CheckWorkSource source;
        OffchainCheckDataHandling offchainCheckDataHandling;
        CheckWorkCallResultInterpretation callResultInterpretation;
        ExecutionDataHandling executionDataHandling;
        // Slot 2: 80 bits
        uint64 maxGasLimit; // In execution gas units for the executor call
        /**
         * @notice If non-zero, this is the expected minimum delay in seconds between the time the work requirement is
         * noticed and the time it is expected to be performed. During this time, if the worker notices the work is no
         * longer required, they will not execute the work and the delay will be reset.
         */
        uint16 executionDelay;
        // Slots 3+
        bytes selector; // Function selector or event topics
        WorkItem[] workItems;
    }

    struct WorkExecutionParams {
        // Slot 1: 256 bits
        address target;
        bytes4 selector; // Function selector
        uint64 maxGasLimit; // In execution gas units for the executor call
        // Slot 2: 128 bits
        uint32 flags; // Bitmask. 1 bit is currently used
        uint64 maxGasPrice; // In wei
        uint16 minBatchSize;
        uint16 maxBatchSize;
    }

    /**
     * @dev A convenience struct to define work parameters in a single struct.
     */
    struct WorkDefinition {
        WorkCheckParams checkParams;
        WorkExecutionParams executionParams;
    }

    /**
     * @dev Not used internally.
     */
    struct BatchMapping {
        bytes32 batchId;
        WorkCheckParams checkParams;
        WorkExecutionParams executionParams;
    }

    enum PoolStatus {
        OPEN,
        NOTICE, // Late payment notice - grace period
        CLOSING,
        CLOSED
    }

    enum OffchainCheckDataHandling {
        NIL,
        IGNORE,
        PREPEND,
        APPEND,
        REPLACE
    }

    enum CheckWorkSource {
        NIL,
        FUNCTION_CALL
        // Future: EVENT_LOG
    }

    enum CheckWorkCallResultInterpretation {
        NIL,
        SUCCESS,
        FAILURE,
        ACI, // AutomationCompatibleInterface
        CONDITIONAL // User-defined condition
    }

    enum ExecutionDataHandling {
        NIL,
        NONE, // Empty bytes
        CHECK_RESULT_DATA_ONLY, // Result from the check call return data
        EXECUTION_DATA_ONLY, // workItem.executionData
        CHECK_DATA_ONLY, // Use the check data as the execution data
        RAW_CHECK_DATA_ONLY // Use the raw check data as the execution data,
    }

    enum ExecutionError {
        NONE,
        BATCH_NOT_FOUND,
        BATCH_DISABLED
    }

    enum Operator {
        NOP, // No operation
        EQ, // Equal
        NE, // Not equal
        GT, // Greater than
        GTE, // Greater than or equal
        LT, // Less than
        LTE // Less than or equal
    }
}
