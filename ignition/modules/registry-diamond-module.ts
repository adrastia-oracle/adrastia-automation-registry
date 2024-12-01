import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import {
    BillingFacet__factory,
    DiamondCutFacet__factory,
    DiamondLoupeFacet__factory,
    OwnershipFacet__factory,
    WorkFacet__factory,
} from "../../typechain-types";
import { ethers } from "hardhat";
import PoolWorkFacetModule from "./pool-work-facet-module";
import PoolBillingFacetModule from "./pool-billing-facet-module";

export const RegistryDiamondModule = buildModule("RegistryDiamond", (m) => {
    const protocolAdmin = m.getParameter("protocolAdmin", m.getAccount(0));

    const diamondCutFaucet = m.contract("DiamondCutFacet", [], {
        id: "DiamondCutFacet",
    });

    const diamondLoupeFaucet = m.contract("DiamondLoupeFacet", [], {
        id: "DiamondLoupeFacet",
    });

    const ownershipFaucet = m.contract("OwnershipFacet", [], {
        id: "OwnershipFacet",
    });

    // DiamondCutFacet functions
    const diamondCutSelector = DiamondCutFacet__factory.createInterface().getFunction("diamondCut").selector;

    // DiamondLoupeFacet functions
    const facetLoupeInterface = DiamondLoupeFacet__factory.createInterface();
    const facetsSelector = facetLoupeInterface.getFunction("facets").selector;
    const facetAddressSelector = facetLoupeInterface.getFunction("facetAddress").selector;
    const facetAddressesSelector = facetLoupeInterface.getFunction("facetAddresses").selector;
    const facetFunctionSelectorsSelector = facetLoupeInterface.getFunction("facetFunctionSelectors").selector;
    const supportsInterfaceSelector = facetLoupeInterface.getFunction("supportsInterface").selector;

    // OwnershipFacet functions
    const ownershipInterface = OwnershipFacet__factory.createInterface();
    const ownerSelector = ownershipInterface.getFunction("owner").selector;
    const transferOwnershipSelector = ownershipInterface.getFunction("transferOwnership").selector;

    // Create the diamond with the standard facets
    const registryDiamond = m.contract(
        "Diamond",
        [
            protocolAdmin,
            [
                {
                    facetAddress: diamondCutFaucet,
                    action: 0, // Add
                    functionSelectors: [diamondCutSelector],
                },
                {
                    facetAddress: diamondLoupeFaucet,
                    action: 0, // Add
                    functionSelectors: [
                        facetsSelector,
                        facetAddressSelector,
                        facetAddressesSelector,
                        facetFunctionSelectorsSelector,
                        supportsInterfaceSelector,
                    ],
                },
                {
                    facetAddress: ownershipFaucet,
                    action: 0, // Add
                    functionSelectors: [ownerSelector, transferOwnershipSelector],
                },
            ],
        ],
        {
            id: "RegistryDiamond",
        },
    );

    // Add registry facets
    // const diamondAsCut = m.contractAt("IDiamondCut", registryDiamond);

    return { registryDiamond };
});

export default RegistryDiamondModule;
