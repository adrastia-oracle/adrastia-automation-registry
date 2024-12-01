// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AutomationPoolTypes} from "./AutomationPoolTypes.sol";

interface CommonErrors is AutomationPoolTypes {
    error PoolNotOpen(PoolStatus status);

    error PoolIsClosed();

    error CheckGasLimitExceeded(bytes32 batchId, uint64 registryGasLimit, uint64 batchGasLimit);

    error ExecutionGasLimitExceeded(bytes32 batchId, uint64 registryGasLimit, uint64 batchGasLimit);

    error BatchNotFound(bytes32 batchId);

    error PoolHasGasDebt(uint256 gasDebt);
}
