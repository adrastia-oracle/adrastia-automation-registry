import { ethers, ignition } from "hardhat";
import RegistryFactoryImplementationModule from "../../ignition/modules/registry-factory-implementation";

async function main() {
    // Deploy a new PoolWorkFacet
    const { registryFactoryImplementation } = await ignition.deploy(RegistryFactoryImplementationModule, {
        deploymentId: "RegistryFactoryImplementation",
    });
    const implementationAddress = registryFactoryImplementation.target;

    console.log("RegistryFactoryImplementation deployed at: " + implementationAddress);

    const beacon = await ethers.getContractAt("UpgradeableBeacon", "0x5D0477E00Afa79055507b32555E9f5f74B42E780");

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
