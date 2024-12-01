import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const PoolImplementationModule = buildModule("PoolImplementation", (m) => {
    const poolImplementation = m.contract("AutomationPool", [], {
        id: "PoolImplementation",
    });

    return { poolImplementation };
});

export default PoolImplementationModule;
