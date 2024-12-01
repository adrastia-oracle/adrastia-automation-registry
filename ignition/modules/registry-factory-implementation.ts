import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const RegistryFactoryImplementationModule = buildModule("RegistryFactoryImplementation", (m) => {
    const registryFactoryImplementation = m.contract("AutomationRegistryFactory", [], {
        id: "RegistryFactoryImplementation",
    });

    return { registryFactoryImplementation };
});

export default RegistryFactoryImplementationModule;
