// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface CommonEvents {
    enum CloseReason {
        ACCOUNT_OVERDUE,
        USER_REQUEST,
        ADMINISTRATIVE
    }

    /******************************************************************************************************************
     * EVENTS - LIFECYCLE
     *****************************************************************************************************************/

    event PoolClosed(CloseReason reason, uint256 timestamp);
}
