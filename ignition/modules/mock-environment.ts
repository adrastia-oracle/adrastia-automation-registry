import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "hardhat";
import ProtocolModule from "./protocol-module";

export default buildModule("MockEnvironment", (m) => {
    const billingToken = m.contract("FakeERC20", ["Fake Token", "FT"], {
        id: "BillingToken",
    });
    const l1GasCalculatorStub = m.contract("L1GasCalculatorStub", [], {
        id: "L1GasCalculatorStub",
    });

    const registryAdmin = m.getParameter("adminAddress", m.getAccount(0));

    const { registryFactory } = m.useModule(ProtocolModule);

    const initialFactoryFeeConfig = {
        poolCreationFee: 100, // 1%
        maintenanceFee: 100, // 1%
        workFee: 100, // 1%
    };

    const initialFactoryRegistryRestrictions = {
        minGasPricePremium: 0, // 0%
        maxGasPricePremium: 100000, // 1000%
        maxGasOverhead: 100_000, // 100,000 gas
        maxMinBalance: ethers.parseEther("10"),
        minWorkFee: 0, // 0%
        maxWorkFee: 1000, // 10%
    };

    const initialRegistryBillingRestrictions = {
        minMaintenanceInterval: 1 * 60 * 60, // 1 hour
        maxMaintenanceInterval: 30 * 24 * 60 * 60, // 30 days
        minGracePeriod: 24 * 60 * 60, // 1 day
        maxGracePeriod: 30 * 24 * 60 * 60, // 30 days
        minClosingPeriod: 1 * 60 * 60, // 1 hour
        maxClosingPeriod: 30 * 24 * 60 * 60, // 30 days
    };

    const initialBillingTokenRestrictions = {
        minPoolCreationFee: ethers.parseUnits("0", 18),
        maxPoolCreationFee: ethers.parseUnits("10000", 18),
        minMaintenanceFeePerDay: ethers.parseUnits("0", 18),
        maxMaintenanceFeePerDay: ethers.parseUnits("10000", 18),
    };

    const setFactoryFeeConfig = m.call(registryFactory, "setFeeConfig", [initialFactoryFeeConfig], {
        id: "SetFactoryFeeConfig",
    });

    const setFactoryRegistryRestrictions = m.call(
        registryFactory,
        "setRegistryRestrictions",
        [initialFactoryRegistryRestrictions],
        {
            id: "SetFactoryRegistryRestrictions",
        },
    );

    const setRegistryBillingRestrictions = m.call(
        registryFactory,
        "setRegistryBillingRestrictions",
        [initialRegistryBillingRestrictions],
        {
            id: "SetRegistryBillingRestrictions",
        },
    );

    const setBillingTokenRestrictions = m.call(
        registryFactory,
        "setBillingTokenRestrictions",
        [billingToken, initialBillingTokenRestrictions],
        {
            id: "SetBillingTokenRestrictions",
        },
    );

    const setGasPriceOracleValidity = m.call(registryFactory, "setGasPriceOracleValidity", [ethers.ZeroAddress, true], {
        id: "SetGasPriceOracleValidity",
    });

    const setL1GasCalculatorValidity1 = m.call(
        registryFactory,
        "setL1GasCalculatorValidity",
        [ethers.ZeroAddress, true],
        {
            id: "SetL1GasCalculatorValidity1",
        },
    );
    const setL1GasCalculatorValidity2 = m.call(
        registryFactory,
        "setL1GasCalculatorValidity",
        [l1GasCalculatorStub, true],
        {
            id: "SetL1GasCalculatorValidity2",
        },
    );

    const gasPriceOracle = m.getParameter("gasPriceOracle", ethers.ZeroAddress);
    const gasPricePremium = m.getParameter("gasPricePremium", 100_00); // 100%
    const gasOverhead = m.getParameter("gasOverhead", 100_000);
    const l1GasCalculator = m.getParameter("l1GasCalculator", ethers.ZeroAddress);

    const initialMetadata = {
        name: "Registry 1",
        description: "The first registry",
        poolType: 0,
    };

    const initialConfig = {
        gasPriceOracle: gasPriceOracle,
        gasPricePremium: gasPricePremium,
        gasOverhead: gasOverhead,
        checkGasLimit: 1e6,
        executionGasLimit: 1e6,
        minBalance: ethers.parseEther("1"),
        workFee: 0, // 1%
        l1GasCalculator: l1GasCalculator,
    };

    const initialBillingConfig = {
        poolCreationFee: 0,
        maintenanceFee: 10_000n,
        maintenanceInterval: 30 * 24 * 60 * 60, // 30 days
        gracePeriod: 5 * 24 * 60 * 60, // 5 days
        closingPeriod: 5 * 24 * 60 * 60, // 5 days
        billingToken: billingToken,
    };

    const initialWorkerConfig = {
        pollingIntervalMs: 1000,
    };

    const createRegistry = m.call(
        registryFactory,
        "createRegistry",
        [registryAdmin, initialMetadata, initialConfig, initialBillingConfig, initialWorkerConfig],
        {
            after: [
                billingToken,
                setFactoryFeeConfig,
                setFactoryRegistryRestrictions,
                setRegistryBillingRestrictions,
                setBillingTokenRestrictions,
                setGasPriceOracleValidity,
                setL1GasCalculatorValidity1,
                setL1GasCalculatorValidity2,
            ],
        },
    );

    const registryAddress = m.readEventArgument(createRegistry, "RegistryCreated", "registry");

    const registry = m.contractAt("AutomationRegistry", registryAddress, {
        id: "Registry",
    });

    const createPool = m.call(registry, "createPool", []);

    const poolAddress = m.readEventArgument(createPool, "PoolCreated", "pool");

    const pool = m.contractAt("AutomationPool", poolAddress, {
        id: "Pool",
    });

    const target = m.contract("MockAutomationTarget", [], {
        id: "AutomationTarget",
    });

    return { registryFactory, registry, pool, target, billingToken, l1GasCalculatorStub: l1GasCalculatorStub };
});
