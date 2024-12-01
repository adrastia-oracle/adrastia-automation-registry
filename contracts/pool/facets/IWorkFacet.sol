// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AutomationPoolTypes} from "../AutomationPoolTypes.sol";

interface IWorkFacet is AutomationPoolTypes {
    /******************************************************************************************************************
     * EVENTS
     *****************************************************************************************************************/

    event WorkCheckParamsUpdated(
        bytes32 indexed batchId,
        WorkCheckParams oldWork,
        WorkCheckParams newWork,
        uint256 timestamp
    );

    event WorkExecutionParamsUpdated(
        bytes32 indexed batchId,
        WorkExecutionParams oldWork,
        WorkExecutionParams newWork,
        uint256 timestamp
    );

    event BatchRegistionChanged(bytes32 indexed batchId, bool registered, uint256 timestamp);

    /******************************************************************************************************************
     * ERRORS
     *****************************************************************************************************************/

    error AggregateCheckGasLimitExceeded(bytes32 batchId, uint64 gasLimit, uint256 aggregateGasLimit);

    error WorkItemExecutionGasLimitExceeded(bytes32 batchId, uint64 gasLimit, uint64 executionGasLimit, uint256 index);

    error InvalidBatchId(bytes32 batchId);

    error BatchAlreadyExists(bytes32 batchId);

    error InvalidBatchExecutionLimit(uint16 limit);

    error BillingCapacityExceeded(uint256 capacity, uint256 paidCapacity);

    error DuplicateWork(bytes32 batchId, WorkItem work);

    error BatchNotChanged(bytes32 batchId);

    error InvalidWorkItemIndex(bytes32 batchId, uint256 index);

    error WorkItemNotChanged(bytes32 batchId, uint256 index);

    error WorkItemHashMismatch(
        bytes32 batchId,
        uint256 index,
        bytes32 previousItemHash,
        bytes32 providedPreviousItemHash
    );

    /******************************************************************************************************************
     * FUNCTIONS
     *****************************************************************************************************************/

    function registerBatch(bytes32 batchId, WorkDefinition calldata work) external;

    function unregisterBatch(bytes32 batchId) external;

    function updateBatch(bytes32 batchId, WorkDefinition calldata newWork) external;

    function pushWork(bytes32 batchId, WorkItem[] calldata workItems) external;

    function setWorkAt(bytes32 batchId, uint256 index, WorkItem calldata workItem) external;

    function setWorkAt(
        bytes32 batchId,
        uint256 index,
        WorkItem calldata workItem,
        bool validatePreviousItem,
        bytes32 previousItemHash
    ) external;

    function removeWorkAt(bytes32 batchId, uint256 index) external;

    function removeWorkAt(bytes32 batchId, uint256 index, bool validatePreviousItem, bytes32 previousItemHash) external;

    function getBatchIds() external view returns (bytes32[] memory batchIds);

    function getBatch(bytes32 batchId) external view returns (WorkDefinition memory);

    function getBatches() external view returns (BatchMapping[] memory);

    function getBatchesCount() external view returns (uint256);

    function batchExists(bytes32 batchId) external view returns (bool);
}
