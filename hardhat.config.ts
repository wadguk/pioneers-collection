import * as dotenv from "dotenv";
import { HardhatUserConfig, task } from "hardhat/config";
import { deployPioneersCollection } from "./scripts/deploy/deployPioneersCollection";
import { deployReferralContracts } from "./scripts/deploy/deployReferralContracts";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-web3";
import "hardhat-contract-sizer";
import "solidity-coverage"

dotenv.config();

function getWallet(): Array<string> {
  return process.env.DEPLOYER_PRIVATE_KEY !== undefined
    ? [process.env.DEPLOYER_PRIVATE_KEY]
    : [];
}

task("deployPioneersCollection", "Deploys collection contract")
  .addPositionalParam("referralRegistry")
  .setAction(async (param, hre) => {
    await deployPioneersCollection(param.referralRegistry, hre);
  });

task("deployReferralContracts", "Deploys referral contracts")
  .setAction(async (param, hre) => {
    await deployReferralContracts(hre);
  });

task("printDeployInfo", "Prints the deploy information", async (taskArgs, hre) => {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Network:", hre.network.name);
  console.log("Network Id:", await hre.web3.eth.net.getId());
  console.log(`Deployer: ${deployer.address}`);
  const balance = await deployer.getBalance();
  console.log(`Deployer balance: ${hre.ethers.utils.formatEther(balance.toString())}`);
});

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10,
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  gasReporter: {
    enabled: true,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY || "",
    gasPriceApi:
      process.env.GAS_PRICE_API ||
      "https://api.etherscan.io/api?module=proxy&action=eth_gasPrice",
    token: "ETH",
    currency: "USD",
  },
  networks: {
    hardhat: {},
    polygonMumbai: {
      url: process.env.POLYGON_MUMBAI_URL || "",
      accounts: getWallet()
    },
    polygon: {
      url: process.env.POLYGON_URL || "",
      accounts: getWallet(),
    },
  },
  etherscan: {
    apiKey: {
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
      polygon: process.env.POLYGONSCAN_API_KEY || "",
    },
  },
};

export default config;