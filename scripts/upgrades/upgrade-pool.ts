import { ethers, ignition } from "hardhat";
import PoolImplementationModule from "../../ignition/modules/pool-implementation";

async function main() {
    // Deploy a new PoolWorkFacet
    const { poolImplementation } = await ignition.deploy(PoolImplementationModule, {
        deploymentId: "PoolImplementation3",
    });
    const implementationAddress = poolImplementation.target;

    console.log("PoolImplementation deployed at: " + implementationAddress);

    const registryFactory = await ethers.getContractAt(
        "AutomationRegistryFactory",
        "0x4fa2B4D88141Cda9d55cD406f495fc4eB2CF7970",
    );

    const beacon = await ethers.getContractAt("UpgradeableBeacon", await registryFactory.poolBeacon());

    console.log("Beacon: " + beacon.target);

    console.log("Beacon owner: " + (await beacon.owner()));

    const [admin] = await ethers.getSigners();

    console.log("Signer address: " + (await admin.getAddress()));

    const upgradeTx = await beacon.upgradeTo(implementationAddress);

    console.log("Upgrade transaction: " + upgradeTx.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
