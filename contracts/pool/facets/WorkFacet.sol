// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IWorkFacet} from "./IWorkFacet.sol";
import {AutomationPoolBase} from "../AutomationPoolBase.sol";
import {IAutomationRegistry} from "../../registry/IAutomationRegistry.sol";
import {Roles} from "../../access/Roles.sol";

contract WorkFacet is IWorkFacet, AutomationPoolBase {
    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function registerBatch(
        bytes32 batchId,
        WorkDefinition calldata work
    ) external virtual override nonReentrant whenOpen {
        _authRegisterWorkBatch();

        if (batchId == bytes32(0)) {
            revert InvalidBatchId(batchId);
        }

        WorkCheckParams memory oldCheckParams = _checkParams[batchId];
        WorkExecutionParams memory oldExecParams = _executionParams[batchId];
        if (oldCheckParams.maxGasLimit != 0) {
            revert BatchAlreadyExists(batchId);
        }

        // Check with billing if we're allowed to register another batch
        BillingState storage billing = _billingState;
        if (_activeBatchIds.length >= billing.nextBatchCapacity) {
            revert BillingCapacityExceeded(_activeBatchIds.length, billing.nextBatchCapacity);
        }

        // Check if pool is open
        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN) {
            revert PoolNotOpen(status);
        }

        // Fetch pool restrictions
        (uint64 registryCheckGasLimit, uint64 registryExecutionGasLimit, ) = IAutomationRegistry(_poolState1.registry)
            .getPoolRestrictions();

        // Validate params
        _validateCheckParams(batchId, work.checkParams, registryCheckGasLimit, true);
        _validateExecutionParams(batchId, work.executionParams, registryExecutionGasLimit);

        // Validate gas limits (internally only)
        _validateCheckGasLimit(work.checkParams.maxGasLimit, work.checkParams.workItems);
        _validateExecutionGasLimit(work.executionParams.maxGasLimit, work.checkParams.workItems);

        _checkParams[batchId] = work.checkParams;
        _executionParams[batchId] = work.executionParams;

        _activeBatchIds.push(batchId);

        _poolState1.activeBatchCount += 1;

        emit BatchRegistionChanged(batchId, true, block.timestamp);

        emit WorkCheckParamsUpdated(batchId, oldCheckParams, work.checkParams, block.timestamp);
        emit WorkExecutionParamsUpdated(batchId, oldExecParams, work.executionParams, block.timestamp);
    }

    function unregisterBatch(bytes32 batchId) external virtual override nonReentrant whenOpen {
        _authUnregisterWorkBatch();

        WorkCheckParams memory checkParams = _checkParams[batchId];
        WorkExecutionParams memory execParams = _executionParams[batchId];
        if (checkParams.maxGasLimit == 0) {
            revert BatchNotFound(batchId);
        }

        uint256 activeBatchesLength = _activeBatchIds.length;
        bytes32[] memory newActiveBatches = new bytes32[](activeBatchesLength - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < activeBatchesLength; ++i) {
            if (_activeBatchIds[i] != batchId) {
                newActiveBatches[j++] = _activeBatchIds[i];
            }
        }
        _activeBatchIds = newActiveBatches;

        _poolState1.activeBatchCount -= 1;

        WorkCheckParams memory emptyWork = WorkCheckParams({
            target: address(0),
            source: CheckWorkSource.NIL,
            offchainCheckDataHandling: OffchainCheckDataHandling.NIL,
            callResultInterpretation: CheckWorkCallResultInterpretation.NIL,
            executionDataHandling: ExecutionDataHandling.NIL,
            maxGasLimit: 0,
            executionDelay: 0,
            chainId: 0,
            selector: "",
            workItems: new WorkItem[](0)
        });
        WorkExecutionParams memory emptyExecParams = WorkExecutionParams({
            target: address(0),
            selector: 0,
            maxGasLimit: 0,
            flags: 0,
            maxGasPrice: 0,
            minBatchSize: 0,
            maxBatchSize: 0
        });

        _checkParams[batchId] = emptyWork;
        _executionParams[batchId] = emptyExecParams;

        emit WorkCheckParamsUpdated(batchId, checkParams, emptyWork, block.timestamp);
        emit WorkExecutionParamsUpdated(batchId, execParams, emptyExecParams, block.timestamp);

        emit BatchRegistionChanged(batchId, false, block.timestamp);
    }

    function updateBatch(bytes32 batchId, WorkDefinition calldata newWork) external virtual override whenOpen {
        _authUpdateWorkBatch();

        WorkCheckParams memory oldCheckParams = _checkParams[batchId];
        WorkExecutionParams memory oldExecParams = _executionParams[batchId];
        if (oldCheckParams.maxGasLimit == 0) {
            revert BatchNotFound(batchId);
        }

        if (
            keccak256(abi.encode(oldCheckParams)) == keccak256(abi.encode(newWork.checkParams)) &&
            keccak256(abi.encode(oldExecParams)) == keccak256(abi.encode(newWork.executionParams))
        ) {
            revert BatchNotChanged(batchId);
        }

        // Fetch pool restrictions
        (uint64 registryCheckGasLimit, uint64 registryExecutionGasLimit, ) = IAutomationRegistry(_poolState1.registry)
            .getPoolRestrictions();

        // Validate params
        _validateCheckParams(batchId, newWork.checkParams, registryCheckGasLimit, true);
        _validateExecutionParams(batchId, newWork.executionParams, registryExecutionGasLimit);

        // Validate gas limits (internally only)
        _validateCheckGasLimit(newWork.checkParams.maxGasLimit, newWork.checkParams.workItems);
        _validateExecutionGasLimit(newWork.executionParams.maxGasLimit, newWork.checkParams.workItems);

        // Update checkParams
        _checkParams[batchId] = WorkCheckParams({
            target: newWork.checkParams.target,
            selector: newWork.checkParams.selector,
            source: newWork.checkParams.source,
            offchainCheckDataHandling: newWork.checkParams.offchainCheckDataHandling,
            callResultInterpretation: newWork.checkParams.callResultInterpretation,
            executionDataHandling: newWork.checkParams.executionDataHandling,
            maxGasLimit: newWork.checkParams.maxGasLimit,
            executionDelay: newWork.checkParams.executionDelay,
            chainId: newWork.checkParams.chainId,
            workItems: newWork.checkParams.workItems
        });

        // Update execParams
        _executionParams[batchId] = WorkExecutionParams({
            target: newWork.executionParams.target,
            selector: newWork.executionParams.selector,
            maxGasLimit: newWork.executionParams.maxGasLimit,
            flags: newWork.executionParams.flags,
            maxGasPrice: newWork.executionParams.maxGasPrice,
            minBatchSize: newWork.executionParams.minBatchSize,
            maxBatchSize: newWork.executionParams.maxBatchSize
        });

        emit WorkCheckParamsUpdated(batchId, oldCheckParams, _checkParams[batchId], block.timestamp);
        emit WorkExecutionParamsUpdated(batchId, oldExecParams, _executionParams[batchId], block.timestamp);
    }

    function pushWork(bytes32 batchId, WorkItem[] calldata workItems) external virtual override whenOpen {
        _authPushWork();

        WorkCheckParams storage checkParams = _checkParams[batchId];
        if (checkParams.maxGasLimit == 0) {
            revert BatchNotFound(batchId);
        }

        WorkCheckParams memory oldCheckParams = checkParams;
        WorkExecutionParams memory execParams = _executionParams[batchId];

        uint256 workLength = workItems.length;
        for (uint256 i = 0; i < workLength; ++i) {
            checkParams.workItems.push(workItems[i]);
        }

        // Fetch pool restrictions
        (uint64 registryCheckGasLimit, uint64 registryExecutionGasLimit, ) = IAutomationRegistry(_poolState1.registry)
            .getPoolRestrictions();

        _validateCheckParams(batchId, checkParams, registryCheckGasLimit, true);
        // We don't change the execution params here, but we validate them to ensure we're still valid
        _validateExecutionParams(batchId, execParams, registryExecutionGasLimit);

        // Validate gas limits (internally only, and only the new items)
        _validateCheckGasLimit(oldCheckParams.maxGasLimit, workItems);
        _validateExecutionGasLimit(execParams.maxGasLimit, workItems);

        emit WorkCheckParamsUpdated(batchId, oldCheckParams, checkParams, block.timestamp);
    }

    function setWorkAt(
        bytes32 batchId,
        uint256 index,
        WorkItem calldata workItem,
        bool validatePreviousItem,
        bytes32 previousItemHash
    ) public virtual override whenOpen {
        _authSetWorkAt();

        WorkCheckParams storage checkParams = _checkParams[batchId];
        if (checkParams.maxGasLimit == 0) {
            revert BatchNotFound(batchId);
        }

        WorkCheckParams memory oldCheckParams = checkParams;
        WorkExecutionParams memory execParams = _executionParams[batchId];

        if (index >= checkParams.workItems.length) {
            revert InvalidWorkItemIndex(batchId, index);
        }

        if (keccak256(abi.encode(checkParams.workItems[index])) == keccak256(abi.encode(workItem))) {
            revert WorkItemNotChanged(batchId, index);
        }

        if (validatePreviousItem) {
            bytes32 itemHash = keccak256(abi.encode(checkParams.workItems[index]));
            if (itemHash != previousItemHash) {
                revert WorkItemHashMismatch(batchId, index, itemHash, previousItemHash);
            }
        }

        checkParams.workItems[index] = workItem;

        (uint64 registryCheckGasLimit, uint64 registryExecutionGasLimit, ) = IAutomationRegistry(_poolState1.registry)
            .getPoolRestrictions();

        _validateCheckParams(batchId, checkParams, registryCheckGasLimit, true);
        // We don't change the execution params here, but we validate them to ensure we're still valid
        _validateExecutionParams(batchId, execParams, registryExecutionGasLimit);

        // Validate gas limits (internally only, and only the new work item)
        WorkItem[] memory newWorkItems = new WorkItem[](1);
        newWorkItems[0] = workItem;
        _validateCheckGasLimit(oldCheckParams.maxGasLimit, newWorkItems);
        _validateExecutionGasLimit(execParams.maxGasLimit, newWorkItems);

        emit WorkCheckParamsUpdated(batchId, oldCheckParams, checkParams, block.timestamp);
    }

    function setWorkAt(bytes32 batchId, uint256 index, WorkItem calldata workItem) external virtual override whenOpen {
        setWorkAt(batchId, index, workItem, false, hex"00");
    }

    function removeWorkAt(
        bytes32 batchId,
        uint256 index,
        bool validatePreviousItem,
        bytes32 previousItemHash
    ) public virtual override whenOpen {
        _authRemoveWorkAt();

        WorkCheckParams storage checkParams = _checkParams[batchId];
        if (checkParams.maxGasLimit == 0) {
            revert BatchNotFound(batchId);
        }

        if (index >= checkParams.workItems.length) {
            revert InvalidWorkItemIndex(batchId, index);
        }

        if (validatePreviousItem) {
            bytes32 itemHash = keccak256(abi.encode(checkParams.workItems[index]));
            if (itemHash != previousItemHash) {
                revert WorkItemHashMismatch(batchId, index, itemHash, previousItemHash);
            }
        }

        WorkCheckParams memory oldCheckParams = checkParams;

        WorkItem[] memory workItems = checkParams.workItems;
        WorkItem[] memory newWorkItems = new WorkItem[](workItems.length - 1);

        uint256 oldLen = workItems.length;
        uint256 j = 0;
        for (uint256 i = 0; i < oldLen; ++i) {
            if (i == index) {
                // Skip the removed work item
                continue;
            }

            newWorkItems[j++] = workItems[i];
        }

        checkParams.workItems = newWorkItems;

        // Fetch pool restrictions
        (uint64 registryCheckGasLimit, uint64 registryExecutionGasLimit, ) = IAutomationRegistry(_poolState1.registry)
            .getPoolRestrictions();

        // Validate params to ensure we're still valid
        _validateCheckParams(batchId, checkParams, registryCheckGasLimit, false);
        _validateExecutionParams(batchId, _executionParams[batchId], registryExecutionGasLimit);

        // Note: We don't need to validate the checkParams here as the work item is being removed
        // We could use it to prevent modifications if the registry changed restrictions and we're invalid now,
        // we choose not to to allow the pool to slowly wind down and stay invalid if they want.

        emit WorkCheckParamsUpdated(batchId, oldCheckParams, checkParams, block.timestamp);
    }

    function removeWorkAt(bytes32 batchId, uint256 index) external virtual override whenOpen {
        removeWorkAt(batchId, index, false, hex"00");
    }

    function getBatchIds() external view virtual override returns (bytes32[] memory) {
        return _activeBatchIds;
    }

    function getBatch(bytes32 batchId) external view virtual override returns (WorkDefinition memory) {
        return WorkDefinition({checkParams: _checkParams[batchId], executionParams: _executionParams[batchId]});
    }

    function getBatches() external view virtual override returns (BatchMapping[] memory) {
        uint256 length = _activeBatchIds.length;
        BatchMapping[] memory batches = new BatchMapping[](length);
        bytes32 batchId;
        for (uint256 i = 0; i < length; ++i) {
            batchId = _activeBatchIds[i];
            batches[i] = BatchMapping({
                batchId: batchId,
                checkParams: _checkParams[batchId],
                executionParams: _executionParams[batchId]
            });
        }

        return batches;
    }

    function getBatchesCount() external view virtual override returns (uint256) {
        return _poolState1.activeBatchCount;
    }

    function batchExists(bytes32 batchId) external view virtual override returns (bool) {
        WorkExecutionParams memory execParams = _executionParams[batchId];

        return execParams.maxGasLimit != 0;
    }

    /******************************************************************************************************************
     * INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function _containsDuplicates(WorkItem[] memory workItems) internal pure returns (bool, WorkItem memory) {
        // TODO: Change the logic? There's now condition and executionData
        // TODO: Remove this? Can be expensive, and we can delegate the responsibility to UIs

        uint256 length = workItems.length;
        for (uint256 i = 0; i < length; ++i) {
            for (uint256 j = i + 1; j < length; ++j) {
                if (keccak256(workItems[i].checkData) == keccak256(workItems[j].checkData)) {
                    return (true, workItems[i]);
                }
            }
        }

        return (
            false,
            WorkItem({
                checkGasLimit: 0,
                executionGasLimit: 0,
                value: 0,
                condition: "",
                checkData: "",
                executionData: ""
            })
        );
    }

    function _validateCheckGasLimit(uint256 maxCheckGasLimit, WorkItem[] memory workItems) internal pure {
        uint256 length = workItems.length;
        for (uint256 i = 0; i < length; ++i) {
            if (workItems[i].checkGasLimit > maxCheckGasLimit) {
                revert("Check gas limit exceeded"); // TODO: Custom error
            }
        }

        // TODO: Also validate CheckWorkCallResultInterpretation against the work item conditions
    }

    function _validateExecutionGasLimit(uint256 maxExecutionGasLimit, WorkItem[] memory workItems) internal pure {
        uint256 length = workItems.length;
        for (uint256 i = 0; i < length; ++i) {
            if (workItems[i].executionGasLimit > maxExecutionGasLimit) {
                revert("Perform gas limit exceeded"); // TODO: Custom error
            }
        }
    }

    function _validateCheckParams(
        bytes32 batchId,
        WorkCheckParams memory checkParams,
        uint64 registryMaxGasLimit,
        bool checkForDuplicates
    ) internal pure {
        if (checkParams.target == address(0)) {
            revert("Invalid target address"); // TODO: Custom error
        }

        if (checkParams.selector.length == 0) {
            // TODO: More validations

            revert("Invalid selector"); // TODO: Custom error
        }

        if (checkParams.source == CheckWorkSource.NIL || checkParams.source > CheckWorkSource.FUNCTION_CALL) {
            revert("Invalid source"); // TODO: Custom error
        }

        if (
            checkParams.offchainCheckDataHandling == OffchainCheckDataHandling.NIL ||
            checkParams.offchainCheckDataHandling > OffchainCheckDataHandling.REPLACE
        ) {
            revert("Invalid offchain check data handling"); // TODO: Custom error
        }

        if (
            checkParams.callResultInterpretation == CheckWorkCallResultInterpretation.NIL ||
            checkParams.callResultInterpretation > CheckWorkCallResultInterpretation.CONDITIONAL
        ) {
            revert("Invalid call result interpretation"); // TODO: Custom error
        }

        if (
            checkParams.executionDataHandling == ExecutionDataHandling.NIL ||
            checkParams.executionDataHandling > ExecutionDataHandling.ACI
        ) {
            revert("Invalid perform data handling"); // TODO: Custom error
        }

        if (checkParams.maxGasLimit == 0) {
            revert("Invalid max gas limit"); // TODO: Custom error
        }

        if (checkForDuplicates) {
            (bool duplicates, WorkItem memory duplicateWork) = _containsDuplicates(checkParams.workItems);
            if (duplicates) {
                revert DuplicateWork(batchId, duplicateWork);
            }
        }

        if (checkParams.maxGasLimit > registryMaxGasLimit) {
            revert CheckGasLimitExceeded(batchId, registryMaxGasLimit, checkParams.maxGasLimit);
        }
    }

    function _validateExecutionParams(
        bytes32 batchId,
        WorkExecutionParams memory execParams,
        uint64 registryMaxGasLimit
    ) internal pure {
        if (execParams.target == address(0)) {
            revert("Invalid target address"); // TODO: Custom error
        }

        if (execParams.selector == 0) {
            revert("Invalid selector"); // TODO: Custom error
        }

        if (execParams.maxGasLimit == 0) {
            revert("Invalid max gas limit"); // TODO: Custom error
        }

        if (execParams.minBatchSize < 1) {
            revert("Invalid min batch size"); // TODO: Custom error
        } else if (execParams.maxBatchSize < execParams.minBatchSize) {
            revert("Invalid max batch size"); // TODO: Custom error
        }

        if (execParams.maxGasPrice == 0) {
            revert("Invalid max gas price"); // TODO: Custom error
        }

        if (execParams.maxGasLimit > registryMaxGasLimit) {
            revert ExecutionGasLimitExceeded(batchId, registryMaxGasLimit, execParams.maxGasLimit);
        }
    }

    /******************************************************************************************************************
     * AUTHORIZATION - POOL WORK MANAGER
     *****************************************************************************************************************/

    function _authRegisterWorkBatch() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authUnregisterWorkBatch() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authUpdateWorkBatch() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authSetWorkBatchEnabled() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authPushWork() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authPopWork() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authSetWorkAt() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authRemoveWorkAt() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}

    function _authSetWork() internal view virtual onlyRole(Roles.POOL_WORK_MANAGER) {}
}
