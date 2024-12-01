import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition-ethers";
import "hardhat-contract-sizer";
import "@nomicfoundation/hardhat-verify";

require("dotenv").config();

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.28",
        settings: {
            viaIR: true,
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        arbitrumSepolia: {
            url: process.env.ARBITRUM_SEPOLIA_URL || "",
            accounts: [process.env.PRIVATE_KEY_DEPLOYER || ""],
        },
    },
    mocha: {
        timeout: 60000, // 60 seconds
    },
    etherscan: {
        apiKey: {
            arbitrumSepolia: process.env.ARBISCAN_SEPOLIA_API_KEY || "",
        },
        customChains: [
            {
                network: "arbitrumSepolia",
                chainId: 421614,
                urls: {
                    apiURL: "https://api-sepolia.arbiscan.io/api",
                    browserURL: "https://sepolia.arbiscan.io",
                },
            },
        ],
    },
};

export default config;
