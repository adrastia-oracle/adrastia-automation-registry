// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControlUpgradeable, AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {Roles} from "./Roles.sol";
import {OpenRoles} from "./OpenRoles.sol";

contract StandardRoleManagement is AccessControlEnumerableUpgradeable, OpenRoles {
    function hasRole(
        bytes32 role,
        address account
    ) public view virtual override(AccessControlUpgradeable, IAccessControl, OpenRoles) returns (bool) {
        return AccessControlUpgradeable.hasRole(role, account);
    }

    /**
     * Gets the address of the contract that manages the specified role.
     *
     * @param role The hash of the role to check.
     */
    function getRoleManagementAddress(bytes32 role) public view virtual returns (address) {
        role; // Silence the unused variable warning

        return address(this);
    }
}
