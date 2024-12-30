// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAutomationPoolStorage} from "./IAutomationPoolStorage.sol";
import {AutomationPoolTypes} from "./AutomationPoolTypes.sol";

contract AutomationPoolStorage is IAutomationPoolStorage, AutomationPoolTypes {
    uint256 public override id;
    address public override executor;
    address public override diamond;

    PoolState1 _poolState1;

    BillingState internal _billingState;

    GasDebt internal _gasDebt;

    uint256 internal _totalGasDebt;

    mapping(bytes32 => WorkCheckParams) internal _checkParams;

    mapping(bytes32 => WorkExecutionParams) internal _executionParams;

    bytes32[] internal _activeBatchIds;

    PoolMetadata internal _metadata;
}
