// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

abstract contract OpenRoles is IAccessControl {
    modifier onlyRoleOrOpenRole(bytes32 role) {
        if (!hasRole(role, address(0))) {
            if (!hasRole(role, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    function hasRole(bytes32 role, address account) public view virtual returns (bool);
}
