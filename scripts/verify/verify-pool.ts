import { AbiCoder, Interface } from "ethers";
import hre from "hardhat";

const POOL_ADDRESS = "0x6fA652Eb9282F8846671Bd13F7Fae7688Eb34f51";

const POOL_BEACON = "0x6D72542e48959daa6552AD828E10d8b0f9E5e1b3";

async function main() {
    await hre.run("verify:verify", {
        contract: "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy",
        address: POOL_ADDRESS,
        constructorArguments: [POOL_BEACON, "0x"],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
