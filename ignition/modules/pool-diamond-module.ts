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

export const PoolDiamondModule = buildModule("PoolDiamond", (m) => {
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
    const poolDiamond = m.contract(
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
            id: "PoolDiamond",
        },
    );

    // Add pool facets
    const diamondAsCut = m.contractAt("IDiamondCut", poolDiamond);

    // Add BillingFacet
    const { billingFacet } = m.useModule(PoolBillingFacetModule);

    const billingFacetInterface = BillingFacet__factory.createInterface();
    const getBillingStateSelector = billingFacetInterface.getFunction("getBillingState").selector;
    const setBillingTargetCapacitySelector = billingFacetInterface.getFunction("setBillingBatchCapacity").selector;
    const calculateChangeCapacityFeesSelector =
        billingFacetInterface.getFunction("calculateChangeCapacityFees").selector;
    const remainingBillingTimeSelector = billingFacetInterface.getFunction("remainingBillingTime").selector;
    const billingActiveSelector = billingFacetInterface.getFunction("billingActive").selector;
    const calculateNextBillingSelector = billingFacetInterface.getFunction("calculateNextBilling").selector;
    const checkBillingWorkSelector = billingFacetInterface.getFunction("checkBillingWork").selector;
    const performBillingWorkSelector = billingFacetInterface.getFunction("performBillingWork").selector;

    m.call(
        diamondAsCut,
        "diamondCut",
        [
            [
                {
                    facetAddress: billingFacet,
                    action: 0, // Add
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
            ethers.ZeroAddress,
            "0x",
        ],
        {
            id: "AddBillingFacetToPoolDiamond",
        },
    );

    // Add WorkFacet
    const { workFacet } = m.useModule(PoolWorkFacetModule);

    const workFacetInterface = WorkFacet__factory.createInterface();
    const registerWorkTargetSelector = workFacetInterface.getFunction("registerBatch").selector;
    const unregisterWorkTargetSelector = workFacetInterface.getFunction("unregisterBatch").selector;
    const updateWorkTargetSelector = workFacetInterface.getFunction("updateBatch").selector;
    // const setWorkTargetEnabledSelector = workFacetInterface.getFunction("setWorkTargetEnabled").selector;
    const pushWorkSelector = workFacetInterface.getFunction("pushWork").selector;
    // const popWorkSelector = workFacetInterface.getFunction("popWork").selector;
    const setWorkAtSelector = workFacetInterface.getFunction(
        "setWorkAt(bytes32,uint256,(uint64,uint64,uint128,bytes,bytes,bytes))",
    ).selector;
    const setWorkAt2Selector = workFacetInterface.getFunction(
        "setWorkAt(bytes32,uint256,(uint64,uint64,uint128,bytes,bytes,bytes),bool,bytes32)",
    ).selector;
    const removeWorkAtSelector = workFacetInterface.getFunction("removeWorkAt(bytes32,uint256)").selector;
    const removeWorkAt2Selector = workFacetInterface.getFunction("removeWorkAt(bytes32,uint256,bool,bytes32)").selector;
    // const setWorkSelector = workFacetInterface.getFunction("setWork").selector;
    const getWorkTargetAddressesSelector = workFacetInterface.getFunction("getBatchIds").selector;
    const getWorkTargetSelector = workFacetInterface.getFunction("getBatch").selector;
    const getWorkTargetsSelector = workFacetInterface.getFunction("getBatches").selector;
    const getWorkTargetsCountSelector = workFacetInterface.getFunction("getBatchesCount").selector;
    const workTargetExistsSelector = workFacetInterface.getFunction("batchExists").selector;

    m.call(
        diamondAsCut,
        "diamondCut",
        [
            [
                {
                    facetAddress: workFacet,
                    action: 0, // Add
                    functionSelectors: [
                        registerWorkTargetSelector,
                        unregisterWorkTargetSelector,
                        updateWorkTargetSelector,
                        // setWorkTargetEnabledSelector,
                        pushWorkSelector,
                        // popWorkSelector,
                        setWorkAtSelector,
                        setWorkAt2Selector,
                        removeWorkAtSelector,
                        removeWorkAt2Selector,
                        // setWorkSelector,
                        getWorkTargetAddressesSelector,
                        getWorkTargetSelector,
                        getWorkTargetsSelector,
                        getWorkTargetsCountSelector,
                        workTargetExistsSelector,
                    ],
                },
            ],
            ethers.ZeroAddress,
            "0x",
        ],
        {
            id: "AddWorkFacetToPoolDiamond",
        },
    );

    return { poolDiamond };
});

export default PoolDiamondModule;
