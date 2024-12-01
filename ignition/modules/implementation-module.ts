import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import PoolExecutorImplementationModule from "./pool-executor-implementation";
import PoolImplementationModule from "./pool-implementation";
import RegistryImplementationModule from "./registry-implementation";
import RegistryFactoryImplementationModule from "./registry-factory-implementation";

export const ImplementationsModule = buildModule("Implementations", (m) => {
    const { registryFactoryImplementation } = m.useModule(RegistryFactoryImplementationModule);
    const { registryImplementation } = m.useModule(RegistryImplementationModule);
    const { poolImplementation } = m.useModule(PoolImplementationModule);
    const { executorImplementation } = m.useModule(PoolExecutorImplementationModule);

    return { registryFactoryImplementation, registryImplementation, poolImplementation, executorImplementation };
});

export default ImplementationsModule;
