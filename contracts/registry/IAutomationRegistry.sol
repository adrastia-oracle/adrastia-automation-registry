// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAutomationRegistry {
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

    event NativeWithdrawn(address indexed caller, address indexed to, uint256 amount, uint256 timestamp);

    function poolType() external view returns (uint16);

    function poolBeacon() external view returns (address);

    function executorBeacon() external view returns (address);

    function getGasData()
        external
        view
        returns (uint256 price, uint256 overhead, uint16 registryFee, address l1GasCalculator, uint256 gasPremium);

    /**
     * @notice Get the pool restrictions for the automation system.
     * @return checkGasLimit The maximum gas limit to check for work.
     * @return executionGasLimit The maximum gas limit to perform work.
     * @return minBalance The minimum balance required to execute the automation.
     */
    function poolRestrictions()
        external
        view
        returns (uint64 checkGasLimit, uint64 executionGasLimit, uint96 minBalance);

    function feeConfig()
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
        uint256 workerDebt,
        uint256 registryDebt
    ) external payable;

    function poolGasDebtRecovered(uint256 poolId, uint256 registryDebt, uint256 workerDebt) external payable;
}
