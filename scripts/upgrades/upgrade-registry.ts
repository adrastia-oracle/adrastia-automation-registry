import { ethers, ignition } from "hardhat";
import RegistryImplementationModule from "../../ignition/modules/registry-implementation";

async function main() {
    // Deploy a new PoolWorkFacet
    const { registryImplementation } = await ignition.deploy(RegistryImplementationModule, {
        deploymentId: "RegistryImplementation6",
    });
    const implementationAddress = registryImplementation.target;

    console.log("RegistryImplementation deployed at: " + implementationAddress);

    const registryFactory = await ethers.getContractAt(
        "AutomationRegistryFactory",
        "0x786881A6d1d3337d51c5bE56362452A4F265CB68",
    );

    const beacon = await ethers.getContractAt("UpgradeableBeacon", await registryFactory.registryBeacon());

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
