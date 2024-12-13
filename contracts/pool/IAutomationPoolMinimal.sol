// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AutomationPoolTypes} from "./AutomationPoolTypes.sol";

interface IAutomationPoolMinimal is AutomationPoolTypes {
    /******************************************************************************************************************
     * STRUCTS
     *****************************************************************************************************************/

    enum Result {
        SUCCESS,
        FAILURE
    }

    enum GasFundMovement {
        DEPOSIT,
        WITHDRAW
    }

    enum GasDebtChange {
        INCREASE,
        DECREASE
    }

    /******************************************************************************************************************
     * EVENTS - GAS
     *****************************************************************************************************************/

    event GasFundsMoved(
        address indexed caller,
        address indexed to,
        GasFundMovement action,
        uint256 amount,
        uint256 timestamp
    );

    event GasDebtUpdated(
        address indexed party,
        GasDebtChange action,
        uint256 amount,
        uint256 newTotalDebt,
        uint256 timestamp
    );

    /******************************************************************************************************************
     * EVENTS - ERC20 WITHDRAWAL
     *****************************************************************************************************************/

    event Erc20Withdrawn(
        address indexed caller,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    /******************************************************************************************************************
     * EVENTS - EXECUTION
     *****************************************************************************************************************/

    event WorkItemExecution(
        bytes32 indexed batchId,
        address indexed target,
        address indexed worker,
        uint256 aggregateCount,
        Result result,
        bytes trigger,
        uint256 gasUsed,
        uint256 timestamp
    );

    event BatchExecution(
        bytes32 indexed batchId,
        address indexed target,
        address indexed worker,
        Result result,
        uint256 numSuccess,
        uint256 numFailures,
        uint256 numSkipped,
        uint256 gasUsed,
        uint256 gasFundsPaid,
        uint256 gasFundsDebt,
        uint256 timestamp
    );

    event ExecutionRestricted(bytes32 indexed batchId, ExecutionError eError, uint256 timestamp);

    /******************************************************************************************************************
     * ERRORS
     *****************************************************************************************************************/

    error WorkerNotAuthorized(address caller);

    error InvalidRegistry(address registry);

    error InvalidAdmin(address admin);

    error BatchDisabled(bytes32 batchId);

    error InsufficientGasFunds(uint256 minBalance, uint256 balance);

    error MinimumBalanceRestriction(uint96 minBalance);

    error PoolAlreadyClosed();

    error GasPriceExceedsLimit(bytes32 batchId, uint256 gasPrice, uint256 maxGasPrice);

    error CallerMustBeRegistry(address account);

    error FailedToCompensateWorker(address worker, uint256 amount);

    error FailedToWithdrawGasFunds(uint256 amount);

    error FailedToInitializeExecutor();

    error CannotDepositNothing();

    error DebtMustBePaidInFull(uint256 totalDebt, uint256 shortfall);

    /******************************************************************************************************************
     * FUNCTIONS
     *****************************************************************************************************************/

    function isBatchActive(bytes32 batchId) external view returns (bool);

    function closePool() external;

    function depositGasFunds() external payable;

    function withdrawGasFunds(address to, uint256 amount) external;

    function getPoolType() external view returns (uint16);

    function getPoolStatus() external view returns (PoolStatus);

    function getTotalGasDebt() external view returns (uint256);

    function checkWork(
        bytes32 batchId,
        OffchainDataProvision calldata offchainData
    )
        external
        returns (
            uint256 workRequiredCount,
            WorkDefinition memory workDefinition,
            CheckedWorkItem[] memory checkedWorkItems
        );

    function performWork(bytes32 batchId, uint256 flags, PerformWorkItem[] calldata workData) external;

    function withdrawErc20(address token, address to, uint256 amount) external;
}
