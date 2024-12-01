// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {AutomationPoolStorage} from "./AutomationPoolStorage.sol";
import {CommonErrors} from "./CommonErrors.sol";
import {CommonEvents} from "./CommonEvents.sol";
import {IAutomationRegistry} from "../registry/IAutomationRegistry.sol";
import {StandardRoleManagement} from "../access/StandardRoleManagement.sol";

contract AutomationPoolBase is
    CommonErrors,
    CommonEvents,
    ReentrancyGuardUpgradeable,
    StandardRoleManagement,
    AutomationPoolStorage
{
    uint8 internal constant FLAG_ACTIVE = 1 << 0;

    /******************************************************************************************************************
     * MODIFIERS
     *****************************************************************************************************************/

    modifier whenOpen() {
        PoolStatus status = getPoolStatus();
        if (status != PoolStatus.OPEN && status != PoolStatus.NOTICE) {
            revert PoolNotOpen(status);
        }
        _;
    }

    modifier whenNotClosed() {
        PoolStatus status = getPoolStatus();
        if (status == PoolStatus.CLOSED) {
            revert PoolIsClosed();
        }
        _;
    }

    modifier whenNotInDebt() {
        if (_totalGasDebt > 0) {
            revert PoolHasGasDebt(_totalGasDebt);
        }
        _;
    }

    /******************************************************************************************************************
     * PUBLIC FUNCTIONS
     *****************************************************************************************************************/

    function getPoolStatus() public view virtual returns (PoolStatus) {
        PoolStatus status = _status;
        if (status == PoolStatus.OPEN) {
            BillingState memory billing = _billingState;
            uint256 nextBillingTime = billing.nextBillingTime;

            if (nextBillingTime == 0) {
                // Billing has not started
                return status;
            } else if (block.timestamp >= billing.nextBillingTime) {
                // We're due for payment
                status = PoolStatus.NOTICE;
            }
        } else if (status == PoolStatus.CLOSING) {
            BillingState memory billing = _billingState;

            uint256 closeTime = billing.closeStartTime + billing.closingPeriod;

            if (block.timestamp >= closeTime) {
                status = PoolStatus.CLOSED;
            }
        }

        return status;
    }
}
