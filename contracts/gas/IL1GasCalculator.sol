// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IL1GasCalculator
 * @author TRILEZ SOFTWARE INC.
 * @notice An interface for a contract that calculates the L1 gas fee for a transaction, with the purpose of charging
 * users for L1 execution costs.
 */
interface IL1GasCalculator {
    function calculateL1GasFee(uint256 calldataSize) external view returns (uint256);
}
