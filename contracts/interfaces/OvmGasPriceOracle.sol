// SPDX-License-Identifier: MIT
pragma solidity >=0.8 <0.9.0;

interface OvmGasPriceOracle {
    function gasPrice() external view returns (uint256);

    function l1BaseFee() external view returns (uint256);

    function overhead() external view returns (uint256);

    function scalar() external view returns (uint256);

    function decimals() external view returns (uint256);

    function isEcotone() external view returns (bool);

    function isFjord() external view returns (bool);

    function blobBaseFee() external view returns (uint256);

    function baseFeeScalar() external view returns (uint32);

    function blobBaseFeeScalar() external view returns (uint32);

    /// @notice returns an upper bound for the L1 fee for a given transaction size.
    /// @dev This function only supports Fjord.
    /// It is provided for callers who wish to estimate L1 transaction costs in the
    /// write path, and is much more gas efficient than `getL1Fee`.
    /// It assumes the worst case of fastlz upper-bound which covers %99.99 txs.
    /// @param _unsignedTxSize Unsigned fully RLP-encoded transaction size to get the L1 fee for.
    /// @return L1 estimated upper-bound fee that should be paid for the tx
    function getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256);
}
