// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAutomationRegistryFactory {
    /******************************************************************************************************************
     * EVENTS - ERC20 WITHDRAWAL
     *****************************************************************************************************************/

    event Erc20Withdrawn(
        address indexed caller,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event NativeWithdrawn(address indexed caller, address indexed to, uint256 amount, uint256 timestamp);

    /**
     * @notice Gets the protocol fee configuration.
     * @return poolCreationFee The fee collected from the registry for creating a pool, in basis points.
     * @return maintenanceFee The fee collected from the registry for maintenance, in basis points.
     * @return workFee The fee collected from the registry for performing work, in basis points.
     */
    function getFeeConfig() external view returns (uint16 poolCreationFee, uint16 maintenanceFee, uint16 workFee);

    function getRegistryRestrictions()
        external
        view
        returns (
            uint32 minGasPricePremium,
            uint32 maxGasPricePremium,
            uint64 maxGasOverhead,
            uint96 maxMinBalance,
            uint16 minWorkFee,
            uint16 maxWorkFee
        );

    function getRegistryBillingRestrictions()
        external
        view
        returns (
            uint32 minMaintenanceInterval,
            uint32 maxMaintenanceInterval,
            uint32 minGracePeriod,
            uint32 maxGracePeriod,
            uint32 minClosingPeriod,
            uint32 maxClosingPeriod
        );

    function getBillingTokenRestrictions(
        address token
    )
        external
        view
        returns (
            uint96 minPoolCreationFee,
            uint96 maxPoolCreationFee,
            uint96 minMaintenanceFeePerDay,
            uint96 maxMaintenanceFeePerDay
        );

    function isValidGasPriceOracle(address oracle) external view returns (bool);

    function isValidL1GasCalculator(address calculator) external view returns (bool);

    function isValidBillingToken(address token) external view returns (bool);
}
