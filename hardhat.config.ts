import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
    solidity: "0.8.25",
    mocha: {
        timeout: 60000, // 60 seconds
    },
};

export default config;
