import { ethers, ignition } from "hardhat";
import { ZeroAddress } from "ethers";
import PoolExecutorImplementationModule from "../../ignition/modules/pool-executor-implementation";
import ProtocolModule from "../../ignition/modules/protocol-module";

async function main() {
    // Deploy a new PoolWorkFacet
    const { executorImplementation } = await ignition.deploy(PoolExecutorImplementationModule, {
        deploymentId: "ExecutorImplementation3",
    });
    const executorImplementationAddress = executorImplementation.target;

    console.log("PoolExecutor deployed at: " + executorImplementationAddress);

    const registryFactory = await ethers.getContractAt(
        "AutomationRegistryFactory",
        "0x786881A6d1d3337d51c5bE56362452A4F265CB68",
    );

    const executorBeacon = await ethers.getContractAt("UpgradeableBeacon", await registryFactory.executorBeacon());

    console.log("Executor beacon: " + executorBeacon.target);

    console.log("Beacon owner: " + (await executorBeacon.owner()));

    const [admin] = await ethers.getSigners();

    console.log("Signer address: " + (await admin.getAddress()));

    const upgradeTx = await executorBeacon.upgradeTo(executorImplementationAddress);

    console.log("Upgrade transaction: " + upgradeTx.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
