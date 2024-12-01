import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const ArbitrumL1GasCalculatorModule = buildModule("ArbitrumL1GasCalculator", (m) => {
    const l1GasCalculator = m.contract("ArbitrumL1GasCalculator");

    return { l1GasCalculator };
});

export default ArbitrumL1GasCalculatorModule;
