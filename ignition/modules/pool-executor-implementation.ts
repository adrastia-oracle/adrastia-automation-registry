import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const PoolExecutorImplementationModule = buildModule("PoolExecutorImplementation", (m) => {
    const executorImplementation = m.contract("PoolExecutor", [], {
        id: "ExecutorImplementation",
    });

    return { executorImplementation };
});

export default PoolExecutorImplementationModule;
