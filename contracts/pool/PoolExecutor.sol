// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IPoolExecutor} from "./IPoolExecutor.sol";
import {IAutomationPoolMinimal} from "./IAutomationPoolMinimal.sol";
import {Roles} from "../access/Roles.sol";

// TODO: Allow the manager to execute arbitrary calls
contract PoolExecutor is Initializable, IPoolExecutor {
    using SafeERC20 for IERC20;

    address public pool;

    error CallerMustBePool(address pool, address caller);

    error CallFailed(address target, Call call);

    modifier onlyRoleFromPool(bytes32 role) {
        if (!IAccessControl(pool).hasRole(role, msg.sender)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    modifier whenNoPoolDebt() {
        if (IAutomationPoolMinimal(pool).getTotalGasDebt() > 0) {
            revert("Pool in debt"); // TODO: Custom revert
        }
        _;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert CallerMustBePool(pool, msg.sender);
        }
        _;
    }

    function initialize(address pool_) public virtual initializer {
        pool = pool_;
    }

    receive() external payable {}

    function withdrawNative(
        address to,
        uint256 amount
    ) external virtual onlyRoleFromPool(Roles.POOL_MANAGER) whenNoPoolDebt {
        payable(to).transfer(amount);
    }

    function withdrawErc20(
        address token,
        address to,
        uint256 amount
    ) external virtual onlyRoleFromPool(Roles.POOL_MANAGER) whenNoPoolDebt {
        IERC20(token).safeTransfer(to, amount);

        emit Erc20Withdrawn(token, to, amount, block.timestamp);
    }

    /// @notice Aggregate calls with a msg value
    /// @notice Reverts if msg.value is less than the sum of the call values
    /// @param calls An array of Call3Value structs
    /// @return returnData An array of Result structs
    function aggregateCalls(
        address target,
        Call[] calldata calls
    ) public payable virtual onlyPool returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call calldata calli;
        uint256 gasStart;
        for (uint256 i = 0; i < length; ++i) {
            gasStart = gasleft();
            Result memory result = returnData[i];
            calli = calls[i];
            (result.success, result.returnData) = target.call{value: calli.value, gas: calli.gasLimit}(calli.callData);
            if (!result.success && !calli.allowFailure) {
                revert CallFailed(target, calli);
            }
            result.gasUsed = gasStart - gasleft();
        }
    }
}
