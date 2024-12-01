import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ImplementationsModule } from "./implementation-module";
import PoolDiamondModule from "./pool-diamond-module";
import RegistryDiamondModule from "./registry-diamond-module";

export const ProtocolModule = buildModule("Protocol", (m) => {
    const { registryFactoryImplementation, registryImplementation, poolImplementation, executorImplementation } =
        m.useModule(ImplementationsModule);

    const { registryDiamond } = m.useModule(RegistryDiamondModule);
    const { poolDiamond } = m.useModule(PoolDiamondModule);

    const protocolAdmin = m.getParameter("protocolAdmin", m.getAccount(0));
    const factoryAdmin = m.getParameter("factoryAdmin", m.getAccount(0));

    const registryFactoryBeacon = m.contract("UpgradeableBeacon", [registryFactoryImplementation, protocolAdmin], {
        id: "RegistryFactoryBeacon",
    });

    const registryFactoryProxy = m.contract("BeaconProxy", [registryFactoryBeacon, "0x"], {
        id: "RegistryFactoryProxy",
    });

    const registryFactory = m.contractAt("AutomationRegistryFactory", registryFactoryProxy);

    m.call(
        registryFactory,
        "initialize",
        [
            protocolAdmin,
            factoryAdmin,
            registryImplementation,
            poolImplementation,
            executorImplementation,
            registryDiamond,
            poolDiamond,
        ],
        {
            id: "InitializeRegistryFactory",
        },
    );

    return { registryFactory };
});

export default ProtocolModule;
