// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AutomationPoolTypes} from "../AutomationPoolTypes.sol";

interface IBillingFacet is AutomationPoolTypes {
    /******************************************************************************************************************
     * EVENTS - BILLING
     *****************************************************************************************************************/

    event MaintenanceFeePaid(address indexed billingToken, uint256 amount, uint256 timestamp);

    event BillingCycleUpdated(
        address indexed billingToken,
        uint256 maintenanceFee, // per batch
        uint256 maintenanceInterval,
        uint256 gracePeriod,
        uint256 closingPeriod,
        uint256 nextBillingTime,
        uint256 timestamp
    );

    event BillingBatchCapacityChanged(uint256 oldCapacity, uint256 newCapacity, uint256 timestamp);

    /******************************************************************************************************************
     * ERRORS
     *****************************************************************************************************************/

    error BillingNotStarted();

    error BillingCycleNotOver(uint32 nextBillingTime);

    error BillingCapacityUnchanged(uint32 capacity);

    error BillingCapacityTooLow(uint32 capacity, uint32 activeBatches);

    /******************************************************************************************************************
     * FUNCTIONS
     *****************************************************************************************************************/

    function getBillingState() external view returns (BillingState memory);

    function setBillingBatchCapacity(uint32 capacity) external;

    function calculateChangeCapacityFees(uint32 capacity) external view returns (IERC20 billingToken, uint256 totalFee);

    function remainingBillingTime() external view returns (uint256);

    function billingActive() external view returns (bool);

    function calculateNextBilling()
        external
        view
        returns (
            IERC20 billingToken,
            uint96 maintenanceFee,
            uint256 totalFee,
            uint32 duration,
            uint32 capacity,
            uint32 gracePeriod,
            uint32 closingPeriod
        );

    function checkBillingWork() external view returns (bool);

    function performBillingWork() external;
}
