import { ethers } from "hardhat";

/* Factory roles */

export const FACTORY_ADMIN = ethers.id("FACTORY_ADMIN_ROLE");
export const FACTORY_MANAGER = ethers.id("FACTORY_MANAGER_ROLE");
export const FACTORY_REGISTRY_DEPLOYER = ethers.id("FACTORY_REGISTRY_DEPLOYER_ROLE");

/* Registry roles */

export const REGISTRY_ADMIN = ethers.id("REGISTRY_ADMIN_ROLE");
export const REGISTRY_FINANCE_MANAGER = ethers.id("REGISTRY_FINANCE_MANAGER_ROLE");
export const REGISTRY_MANAGER = ethers.id("REGISTRY_MANAGER_ROLE");
export const REGISTRY_POOL_DEPLOYER = ethers.id("REGISTRY_POOL_DEPLOYER_ROLE");

/* Pool roles */

export const POOL_ADMIN = ethers.id("POOL_ADMIN_ROLE");
export const POOL_MANAGER = ethers.id("POOL_MANAGER_ROLE");

/* Worker roles */

export const WORKER_ADMIN = ethers.id("WORKER_ADMIN_ROLE");
export const WORKER_MANAGER = ethers.id("WORKER_MANAGER_ROLE");
export const WORKER = ethers.id("WORKER_ROLE");
