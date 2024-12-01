// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IL1GasCalculator} from "../gas/IL1GasCalculator.sol";

contract L1GasCalculatorStub is IL1GasCalculator {
    uint256 public gasFee;

    function setGasFee(uint256 _gasFee) external {
        gasFee = _gasFee;
    }

    function calculateL1GasFee(uint256) external view override returns (uint256) {
        return gasFee;
    }
}
