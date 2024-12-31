import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const OptimismL1GasCalculatorModule = buildModule("OptimismL1GasCalculator", (m) => {
    const l1GasCalculator = m.contract("OptimismL1GasCalculator");

    return { l1GasCalculator };
});

export default OptimismL1GasCalculatorModule;
