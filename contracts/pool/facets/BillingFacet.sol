// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IBillingFacet} from "./IBillingFacet.sol";
import {AutomationPoolBase} from "../AutomationPoolBase.sol";
import {IAutomationRegistry} from "../../registry/IAutomationRegistry.sol";
import {Roles} from "../../access/Roles.sol";

contract BillingFacet is IBillingFacet, AutomationPoolBase {
    using SafeERC20 for IERC20;

    /******************************************************************************************************************
     * EXTERNAL FUNCTIONS
     *****************************************************************************************************************/

    function getBillingState() external view virtual override returns (BillingState memory) {
        return _billingState;
    }

    function setBillingBatchCapacity(uint32 capacity) external virtual override nonReentrant {
        _authSetBillingBatchCapacity();

        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN) {
            // We can only change billing batch capacity when the pool is open
            revert PoolNotOpen(status);
        }

        BillingState storage billing = _billingState;
        uint256 nextBatchCapacity = billing.nextBatchCapacity;
        uint256 paidBatchCapacity = billing.paidBatchCapacity;
        if (capacity == nextBatchCapacity) {
            revert BillingCapacityUnchanged(capacity);
        } else if (capacity < nextBatchCapacity) {
            // Decrease the batch capacity. Ensure that this new capacity is less than or equal to the active
            // batch count.
            uint32 activeBatchesLength = uint32(_activeBatchIds.length);
            if (capacity < activeBatchesLength) {
                revert BillingCapacityTooLow(capacity, activeBatchesLength);
            }

            billing.nextBatchCapacity = capacity;
        } else {
            // Capacity is larger than the next batch capacity.

            address registry_ = registry;

            (
                IERC20 billingToken,
                uint256 maintenanceFeeProRata,
                uint32 maintenanceInterval,
                uint96 maintenanceFee,
                uint32 gracePeriod,
                uint32 closingPeriod
            ) = _calculateIncreaseCapacityFees(registry_, billing, paidBatchCapacity, capacity);

            if (maintenanceFeeProRata > 0) {
                // Transfer the maintenance fee to the registry
                billingToken.safeTransfer(address(registry_), maintenanceFeeProRata);

                // Inform the registry that the maintenance fee has been collected
                IAutomationRegistry(registry_).poolMaintenanceFeeCollectedCallback(
                    id,
                    billingToken,
                    maintenanceFeeProRata
                );

                emit MaintenanceFeePaid(address(billingToken), maintenanceFeeProRata, block.timestamp);
            }

            // Update the billing state
            if (capacity > billing.paidBatchCapacity) {
                // We've paid for more capacity.
                // This check avoids lowering the paid capacity in edge cases.
                billing.paidBatchCapacity = capacity;
            }
            billing.nextBatchCapacity = capacity;

            if (billing.nextBillingTime == 0) {
                // First billing cycle
                billing.lastBillingTime = uint32(block.timestamp);
                billing.nextBillingTime = uint32(block.timestamp + maintenanceInterval);

                billing.lastMaintenanceFee = maintenanceFee;
                billing.lastBillingToken = address(billingToken);

                billing.gracePeriod = gracePeriod;
                billing.closingPeriod = closingPeriod;

                emit BillingCycleUpdated(
                    address(billingToken),
                    maintenanceFee,
                    maintenanceInterval,
                    gracePeriod,
                    closingPeriod,
                    billing.nextBillingTime,
                    block.timestamp
                );
            }
        }

        emit BillingBatchCapacityChanged(nextBatchCapacity, capacity, block.timestamp);
    }

    /**
     * @notice Calculates the immediate pro rata maintenance fee for changing the batch capacity.
     *
     * @param capacity The new batch capacity.
     *
     * @return billingToken The billing token.
     * @return totalFee The pro rata maintenance fee for the change in capacity, denominated in the billing token.
     * Returns 0 if the capacity is less than or equal to the current paid batch capacity.
     */

    function calculateChangeCapacityFees(
        uint32 capacity
    ) external view virtual override returns (IERC20 billingToken, uint256 totalFee) {
        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN) {
            // We can only change billing batch capacity when the pool is open
            revert PoolNotOpen(status);
        }

        BillingState storage billing = _billingState;
        uint256 paidBatchCapacity = billing.paidBatchCapacity;

        if (capacity <= paidBatchCapacity) {
            uint256 remainingBillingTime_ = remainingBillingTime();

            if (remainingBillingTime_ == 0) {
                // Not in an active billing cycle. Get the billing token from the registry.

                (address billingToken_, , , , , ) = IAutomationRegistry(registry).feeConfig();

                billingToken = IERC20(billingToken_);
            } else {
                // Active billing cycle. Use the last (current) billing token.
                billingToken = IERC20(billing.lastBillingToken);
            }

            // No immediate fees to decrease capacity or for it to remain the same
            return (billingToken, 0);
        }

        (billingToken, totalFee, , , , ) = _calculateIncreaseCapacityFees(
            registry,
            billing,
            paidBatchCapacity,
            capacity
        );
    }

    function checkBillingWork() external view virtual override returns (bool) {
        if (!billingActive()) {
            return false;
        }

        if (remainingBillingTime() > 0) {
            return false;
        }

        (IERC20 billingToken, , uint256 totalFee, , , , ) = calculateNextBilling();
        if (billingToken.balanceOf(address(this)) < totalFee) {
            if (block.timestamp >= _billingState.nextBillingTime + _billingState.gracePeriod) {
                // Grace period has passed. Signal to close the pool.
                return true;
            }

            // Not enough funds, but still in grace period
            return false;
        }

        return true;
    }

    function performBillingWork() external virtual override nonReentrant {
        BillingState storage billing = _billingState;
        if (billing.nextBillingTime == 0) {
            revert BillingNotStarted();
        }

        if (!billingActive()) {
            // Billing is/was active, so the pool must not be open anymore
            revert PoolNotOpen(getPoolStatus());
        }

        if (remainingBillingTime() > 0) {
            revert BillingCycleNotOver(billing.nextBillingTime);
        }

        // Calculate the maintenance fee
        (
            IERC20 billingToken,
            uint96 maintenanceFee,
            uint256 totalFee,
            uint32 duration,
            uint32 capacity,
            uint32 gracePeriod,
            uint32 closingPeriod
        ) = calculateNextBilling();

        // Transfer the maintenance fee to the registry
        if (totalFee > 0) {
            if (billingToken.balanceOf(address(this)) < totalFee) {
                if (block.timestamp >= billing.nextBillingTime + billing.gracePeriod) {
                    // Grace period has passed. Start closing the pool.
                    _status = PoolStatus.CLOSING;
                    billing.closeStartTime = uint32(block.timestamp);

                    emit PoolClosed(CloseReason.ACCOUNT_OVERDUE, block.timestamp);

                    return;
                }
            }

            address registry_ = registry;

            // Note: This may revert if the pool does not have enough funds
            billingToken.safeTransfer(registry_, totalFee);

            // Inform the registry that the maintenance fee has been collected
            IAutomationRegistry(registry_).poolMaintenanceFeeCollectedCallback(id, billingToken, totalFee);

            emit MaintenanceFeePaid(address(billingToken), totalFee, block.timestamp);
        }

        // Update the billing state
        billing.lastBillingTime = billing.nextBillingTime;
        billing.lastMaintenanceFee = maintenanceFee;
        billing.nextBillingTime += duration;
        billing.paidBatchCapacity = capacity;
        billing.lastBillingToken = address(billingToken);
        billing.gracePeriod = gracePeriod;
        billing.closingPeriod = closingPeriod;

        emit BillingCycleUpdated(
            address(billingToken),
            maintenanceFee,
            duration,
            gracePeriod,
            closingPeriod,
            billing.nextBillingTime,
            block.timestamp
        );
    }

    /******************************************************************************************************************
     * PUBLIC FUNCTIONS
     *****************************************************************************************************************/

    function remainingBillingTime() public view virtual override returns (uint256) {
        BillingState memory billing = _billingState;
        if (billing.nextBillingTime == 0 || billing.nextBillingTime <= block.timestamp) {
            return 0;
        }

        return billing.nextBillingTime - block.timestamp;
    }

    function billingActive() public view virtual override returns (bool) {
        // Check pool status
        PoolStatus status = getPoolStatus();
        if (status == PoolStatus.CLOSING || status == PoolStatus.CLOSED) {
            return false;
        }

        // Check billing state
        BillingState memory billing = _billingState;

        return billing.nextBillingTime > 0;
    }

    function calculateNextBilling()
        public
        view
        virtual
        override
        returns (
            IERC20 billingToken,
            uint96 maintenanceFee,
            uint256 totalFee,
            uint32 duration,
            uint32 capacity,
            uint32 gracePeriod,
            uint32 closingPeriod
        )
    {
        PoolStatus status = getPoolStatus();
        if (status == PoolStatus.CLOSING || status == PoolStatus.CLOSED) {
            revert PoolNotOpen(status);
        }

        BillingState memory billing = _billingState;
        (
            address billingToken_,
            ,
            uint96 maintenanceFee_,
            uint32 maintenanceInterval,
            uint32 gracePeriod_,
            uint32 closingPeriod_
        ) = IAutomationRegistry(registry).feeConfig();

        billingToken = IERC20(billingToken_);
        maintenanceFee = maintenanceFee_;
        totalFee = uint256(maintenanceFee_) * billing.nextBatchCapacity;
        duration = maintenanceInterval;
        capacity = billing.nextBatchCapacity;
        gracePeriod = gracePeriod_;
        closingPeriod = closingPeriod_;
    }

    /******************************************************************************************************************
     * INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /**
     * @notice Calculates the immediate pro rata maintenance fee for increasing the batch capacity.
     *
     * @param billing The pool's billing configuration.
     * @param paidBatchCapacity The pool's current paid batch capacity.
     * @param newBatchCapacity The new batch capacity.
     *
     * @return billingToken The billing token.
     * @return maintenanceFeeProRata The pro rata maintenance fee for the increase in capacity, denominated in the
     * billing token.
     * @return maintenanceInterval The maintenance interval for the pool.
     * @return maintenanceFee The maintenance fee for the pool, per batch.
     */
    function _calculateIncreaseCapacityFees(
        address registry_,
        BillingState storage billing,
        uint256 paidBatchCapacity,
        uint256 newBatchCapacity
    )
        internal
        view
        virtual
        returns (
            IERC20 billingToken,
            uint256 maintenanceFeeProRata,
            uint32 maintenanceInterval,
            uint96 maintenanceFee,
            uint32 gracePeriod,
            uint32 closingPeriod
        )
    {
        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN) {
            // We can only change billing batch capacity when the pool is open
            revert PoolNotOpen(status);
        }

        // Determine the difference between the new capacity and the paid capacity.
        uint256 capacityDiff;
        if (newBatchCapacity < paidBatchCapacity) {
            // Decrease the batch capacity. Set the difference to zero to make the fees zero.
            capacityDiff = 0;
        } else {
            // Increase the batch capacity (or keep it the same
            capacityDiff = newBatchCapacity - paidBatchCapacity;
        }

        // Get fee config
        (
            address billingToken_,
            ,
            uint96 maintenanceFee_,
            uint32 maintenanceInterval_,
            uint32 gracePeriod_,
            uint32 closingPeriod_
        ) = IAutomationRegistry(registry_).feeConfig();

        // Calculate the additional maintenance fee for this billing cycle, pro rata.
        uint256 lastBillingTime = billing.lastBillingTime;
        uint256 nextBillingTime = billing.nextBillingTime;
        uint256 proportionRemaining;
        if (nextBillingTime == 0) {
            // First billing cycle
            proportionRemaining = 1e6;
            maintenanceInterval = maintenanceInterval_;
            maintenanceFee = maintenanceFee_;
            billingToken = IERC20(billingToken_);
            gracePeriod = gracePeriod_;
            closingPeriod = closingPeriod_;
        } else {
            // Active billing cycle
            uint256 billingCycleDuration = nextBillingTime - lastBillingTime;
            proportionRemaining = Math.ceilDiv(
                uint256(billing.nextBillingTime - block.timestamp) * 1e6,
                billingCycleDuration
            );
            maintenanceInterval = uint32(billingCycleDuration);
            maintenanceFee = billing.lastMaintenanceFee;
            billingToken = IERC20(billing.lastBillingToken);
            gracePeriod = billing.gracePeriod;
            closingPeriod = billing.closingPeriod;
        }
        maintenanceFeeProRata = Math.ceilDiv((maintenanceFee * capacityDiff * proportionRemaining), 1e6);
    }

    /******************************************************************************************************************
     * AUTHORIZATION - POOL MANAGER
     *****************************************************************************************************************/

    function _authSetBillingBatchCapacity() internal view virtual onlyRole(Roles.POOL_MANAGER) {}
}
