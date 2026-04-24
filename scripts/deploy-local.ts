// 本地部署脚本：MyNFT + 旧版市场 + V1新版市场
import { network } from "hardhat";
const { ethers } = await network.create();

async function main() {
  const deployer = await ethers.provider.getSigner();
  console.log("========================================");
  console.log("本地部署账户:", await deployer.getAddress());

  // 1. 部署基础NFT合约
  const nft = await ethers.deployContract("MyNFT");
  await nft.waitForDeployment();
  console.log("✅ MyNFT 部署地址:", await nft.getAddress());

  // 2. 部署旧版交易市场
  const marketOld = await ethers.deployContract("NFTMarketplace");
  await marketOld.waitForDeployment();
  console.log("✅ NFTMarketplace(旧版) 地址:", await marketOld.getAddress());

  // 3. 部署V1升级版市场
  const marketV1 = await ethers.deployContract("NFTMarketplaceV1");
  await marketV1.waitForDeployment();
  console.log("✅ NFTMarketplaceV1(升级版) 地址:", await marketV1.getAddress());
  console.log("========================================");
  console.log("本地全部合约部署完成");
}

main().catch((error) => {
  console.error("部署失败:", error);
  process.exitCode = 1;
});