// Sepolia 测试网部署脚本
import { network } from "hardhat";
const { ethers } = await network.create();

async function main() {
  const deployer = await ethers.provider.getSigner();
  console.log("========================================");
  console.log("Sepolia部署钱包:", await deployer.getAddress());

  const nft = await ethers.deployContract("MyNFT");
  await nft.waitForDeployment();
  console.log("✅ MyNFT(SEPOLIA):", await nft.getAddress());

  const marketV1 = await ethers.deployContract("NFTMarketplaceV1");
  await marketV1.waitForDeployment();
  console.log("✅ MarketplaceV1(SEPOLIA):", await marketV1.getAddress());

  console.log("Sepolia 测试网升级合约部署完成");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});