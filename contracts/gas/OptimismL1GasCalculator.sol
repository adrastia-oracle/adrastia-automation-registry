// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IL1GasCalculator} from "./IL1GasCalculator.sol";
import {OvmGasPriceOracle} from "../interfaces/OvmGasPriceOracle.sol";

contract OptimismL1GasCalculator is IL1GasCalculator {
    OvmGasPriceOracle public constant GAS_PRICE_ORACLE = OvmGasPriceOracle(0x420000000000000000000000000000000000000F);

    uint256 internal constant OP_GAS_CONSTANT = 68 * 16;

    /**
     * @notice Calculate the L1 gas fee for a transaction.
     * @dev Based on https://github.com/ethereum-optimism/optimism/blob/d5dfd515a844ce16b8488af6a95fd45d95ed7e78/packages/contracts-bedrock/src/L2/GasPriceOracle.sol
     *
     * @param dataSize The size of the calldata.
     *
     * @return The L1 gas fee.
     */
    function calculateL1GasFee(uint256 dataSize) external view override returns (uint256) {
        // Try to call the L1FeeUpperBound function on the GasPriceOracle contract. Only works if Fjord is enabled.
        (bool fSuccess, bytes memory fData) = address(GAS_PRICE_ORACLE).staticcall(
            abi.encodeWithSelector(GAS_PRICE_ORACLE.getL1FeeUpperBound.selector)
        );
        if (fSuccess && fData.length == 32) {
            uint256 l1Fee = abi.decode(fData, (uint256));

            return l1Fee;
        }
        // Not Fjord from here on.

        uint256 l1GasUsed = dataSize * 16 + OP_GAS_CONSTANT;

        // Let's see if ecotone is enabled.
        (bool eSuccess, bytes memory eData) = address(GAS_PRICE_ORACLE).staticcall(
            abi.encodeWithSelector(GAS_PRICE_ORACLE.isEcotone.selector)
        );
        if (eSuccess && eData.length == 32) {
            bool isEcotone = abi.decode(eData, (bool));
            if (isEcotone) {
                uint256 scaledBaseFee = GAS_PRICE_ORACLE.baseFeeScalar() * 16 * GAS_PRICE_ORACLE.l1BaseFee();
                uint256 scaledBlobBaseFee = GAS_PRICE_ORACLE.blobBaseFeeScalar() * GAS_PRICE_ORACLE.blobBaseFee();
                uint256 fee = l1GasUsed * (scaledBaseFee + scaledBlobBaseFee);

                return fee / (16 * 10 ** GAS_PRICE_ORACLE.decimals());
            }
        }
        // Not ecotone from here on. Bedrock.
        {
            uint256 fee = (l1GasUsed + GAS_PRICE_ORACLE.overhead()) *
                GAS_PRICE_ORACLE.l1BaseFee() *
                GAS_PRICE_ORACLE.scalar();

            return fee / (10 ** GAS_PRICE_ORACLE.decimals());
        }
    }
}
