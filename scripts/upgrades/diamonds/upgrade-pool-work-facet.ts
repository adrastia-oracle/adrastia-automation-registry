import { ethers, ignition } from "hardhat";
import { WorkFacet__factory } from "../../../typechain-types";
import { default as PoolWorkFacetModule } from "../../../ignition/modules/pool-work-facet-module";
import { ZeroAddress } from "ethers";

const POOL_DIAMOND = "0x4a22152e8064bc77c6261c38cd1A88ee0788Dd3d";

async function main() {
    // Deploy a new PoolWorkFacet
    const { workFacet } = await ignition.deploy(PoolWorkFacetModule, {
        deploymentId: "PoolWorkFacet2",
    });

    console.log("WorkFacet deployed at: " + workFacet.target);

    // Conver the PoolDiamond to IDiamondCut
    const diamondAsCut = await ethers.getContractAt("IDiamondCut", POOL_DIAMOND);

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

    // Replace selectors
    const tx = await diamondAsCut.diamondCut(
        [
            {
                facetAddress: workFacet.target,
                action: 1, // Replace
                functionSelectors: [
                    registerWorkTargetSelector,
                    unregisterWorkTargetSelector,
                    updateWorkTargetSelector,
                    // setWorkTargetEnabledSelector,
                    pushWorkSelector,
                    // popWorkSelector,
                    setWorkAtSelector,
                    // setWorkSelector,
                    getWorkTargetAddressesSelector,
                    getWorkTargetSelector,
                    getWorkTargetsSelector,
                    getWorkTargetsCountSelector,
                    removeWorkAtSelector,
                    workTargetExistsSelector,
                    setWorkAt2Selector,
                    removeWorkAt2Selector,
                ],
            },
            /*{
                facetAddress: workFacet.target,
                action: 0, // Add
                functionSelectors: [setWorkAt2Selector, removeWorkAt2Selector],
            },*/
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
