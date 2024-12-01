// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IL1GasCalculator} from "./IL1GasCalculator.sol";
import {ArbGasInfo} from "../interfaces/ArbGasInfo.sol";

contract ArbitrumL1GasCalculator is IL1GasCalculator {
    ArbGasInfo public constant ARB_GAS_INFO = ArbGasInfo(0x000000000000000000000000000000000000006C);

    function calculateL1GasFee(uint256) external view override returns (uint256) {
        return ARB_GAS_INFO.getCurrentTxL1GasFees();
    }
}
