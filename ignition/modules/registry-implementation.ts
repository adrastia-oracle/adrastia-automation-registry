import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const RegistryImplementationModule = buildModule("RegistryImplementation", (m) => {
    const registryImplementation = m.contract("AutomationRegistry", [], {
        id: "RegistryImplementation",
    });

    return { registryImplementation };
});

export default RegistryImplementationModule;
