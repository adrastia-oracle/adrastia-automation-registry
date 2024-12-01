// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IAutomationPoolStorage {
    function id() external view returns (uint256);

    function registry() external view returns (address);

    function executor() external view returns (address);

    function diamond() external view returns (address);
}
