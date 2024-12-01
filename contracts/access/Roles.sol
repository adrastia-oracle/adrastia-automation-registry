// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.9.0;

library Roles {
    /******************************************************************************************************************
     * PROTOCOL
     *****************************************************************************************************************/

    bytes32 public constant PROTOCOL_ADMIN = keccak256("PROTOCOL_ADMIN_ROLE");

    /******************************************************************************************************************
     * FACTORY
     *****************************************************************************************************************/

    bytes32 public constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN_ROLE");

    bytes32 public constant FACTORY_MANAGER = keccak256("FACTORY_MANAGER_ROLE");

    bytes32 public constant FACTORY_REGISTRY_DEPLOYER = keccak256("FACTORY_REGISTRY_DEPLOYER_ROLE");

    /******************************************************************************************************************
     * REGISTRY
     *****************************************************************************************************************/

    bytes32 public constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN_ROLE");

    bytes32 public constant REGISTRY_FINANCE_MANAGER = keccak256("REGISTRY_FINANCE_MANAGER_ROLE");

    bytes32 public constant REGISTRY_MANAGER = keccak256("REGISTRY_MANAGER_ROLE");

    bytes32 public constant REGISTRY_POOL_DEPLOYER = keccak256("REGISTRY_POOL_DEPLOYER_ROLE");

    /******************************************************************************************************************
     * WORKER
     *****************************************************************************************************************/

    bytes32 public constant WORKER_ADMIN = keccak256("WORKER_ADMIN_ROLE");

    bytes32 public constant WORKER_MANAGER = keccak256("WORKER_MANAGER_ROLE");

    bytes32 public constant WORKER = keccak256("WORKER_ROLE");

    /******************************************************************************************************************
     * POOL
     *****************************************************************************************************************/

    bytes32 public constant POOL_ADMIN = keccak256("POOL_ADMIN_ROLE");

    bytes32 public constant POOL_MANAGER = keccak256("POOL_MANAGER_ROLE");

    /**
     * @notice Role for managing pool work.
     */
    bytes32 public constant POOL_WORK_MANAGER = keccak256("POOL_WORK_MANAGER_ROLE");
}
