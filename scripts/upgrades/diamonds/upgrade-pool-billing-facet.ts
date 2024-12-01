import { ethers, ignition } from "hardhat";
import { default as PoolWorkFacetModule } from "../../../ignition/modules/pool-work-facet-module";
import { ZeroAddress } from "ethers";
import { BillingFacet__factory } from "../../../typechain-types";

async function main() {
    // Deploy a new PoolWorkFacet
    const { workFacet } = await ignition.deploy(PoolWorkFacetModule, {
        deploymentId: "PoolBillingFacet",
    });

    console.log("WorkFacet deployed at: " + workFacet.target);

    // Conver the PoolDiamond to IDiamondCut
    const diamondAsCut = await ethers.getContractAt("IDiamondCut", "0xC8a4609C18ca3628676C0478779037898ab498f4");

    const billingFacetInterface = BillingFacet__factory.createInterface();
    const getBillingStateSelector = billingFacetInterface.getFunction("getBillingState").selector;
    const setBillingTargetCapacitySelector = billingFacetInterface.getFunction("setBillingTargetCapacity").selector;
    const calculateChangeCapacityFeesSelector =
        billingFacetInterface.getFunction("calculateChangeCapacityFees").selector;
    const remainingBillingTimeSelector = billingFacetInterface.getFunction("remainingBillingTime").selector;
    const billingActiveSelector = billingFacetInterface.getFunction("billingActive").selector;
    const calculateNextBillingSelector = billingFacetInterface.getFunction("calculateNextBilling").selector;
    const checkBillingWorkSelector = billingFacetInterface.getFunction("checkBillingWork").selector;
    const performBillingWorkSelector = billingFacetInterface.getFunction("performBillingWork").selector;

    // Replace selectors
    const tx = await diamondAsCut.diamondCut(
        [
            {
                facetAddress: workFacet.target,
                action: 1, // Replace
                functionSelectors: [
                    getBillingStateSelector,
                    setBillingTargetCapacitySelector,
                    calculateChangeCapacityFeesSelector,
                    remainingBillingTimeSelector,
                    billingActiveSelector,
                    calculateNextBillingSelector,
                    checkBillingWorkSelector,
                    performBillingWorkSelector,
                ],
            },
        ],
        ZeroAddress,
        "0x",
    );

    console.log("Diamond cut tx: " + tx.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
