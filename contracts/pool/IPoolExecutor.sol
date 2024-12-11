// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IPoolExecutor {
    struct Call {
        bool allowFailure;
        uint64 gasLimit;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }

    function withdrawNative(address to, uint256 amount) external;

    function withdrawErc20(address token, address to, uint256 amount) external;

    function aggregateCalls(
        address target,
        Call[] calldata calls
    ) external payable returns (Result[] memory returnData);
}
