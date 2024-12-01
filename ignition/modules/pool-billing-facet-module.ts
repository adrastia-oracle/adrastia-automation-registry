import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export const PoolBillingFacetModule = buildModule("PoolBillingFacet", (m) => {
    const billingFacet = m.contract("BillingFacet", [], {
        id: "BillingFacet",
    });

    return { billingFacet };
});

export default PoolBillingFacetModule;
