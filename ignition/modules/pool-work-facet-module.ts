import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const PoolWorkFacetModule = buildModule("PoolWorkFacet", (m) => {
    // Add WorkFacet
    const workFacet = m.contract("WorkFacet", [], {
        id: "WorkFacet",
    });

    return { workFacet };
});

export default PoolWorkFacetModule;
