// NFT市场 旧版 → V1升级版 完整流程测试
import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

describe("NFTMarketplace 旧版 → V1 升级兼容测试", function () {
  const testURI = "ipfs://market-demo-nft";
  const mintCost = ethers.parseEther("0.01");
  const salePrice = ethers.parseEther("0.1");

  it("【旧版市场】正常上架NFT + 购买NFT(buyNFT)", async function () {
    // 部署依赖
    const nft = await ethers.deployContract("MyNFT");
    const marketOld = await ethers.deployContract("NFTMarketplace");
    const seller = await ethers.provider.getSigner();
    const sellerAddr = await seller.getAddress();

    // 1. 卖家铸造NFT
    await nft.mint(testURI, { value: mintCost });
    // 2. 授权市场合约转移NFT
    await nft.approve(marketOld.target, 1n);

    // 3. 上架，校验原生 NFTListed 事件
    await expect(marketOld.listNFT(nft.target, 1n, salePrice))
      .to.emit(marketOld, "NFTListed")
      .withArgs(1n, sellerAddr, nft.target, 1n, salePrice);

    // 4. 买家账号购买
    const buyer = await ethers.provider.getSigner(1);
    await marketOld.connect(buyer).buyNFT(1n, { value: salePrice });

    // 5. 校验NFT所有权转移
    expect(await nft.ownerOf(1n)).to.equal(await buyer.getAddress());
  });

  it("【V1升级版市场】同源buyNFT接口，功能完全兼容", async function () {
    const nft = await ethers.deployContract("MyNFT");
    const marketV1 = await ethers.deployContract("NFTMarketplaceV1");
    const seller = await ethers.provider.getSigner();
    const sellerAddr = await seller.getAddress();

    await nft.mint(testURI, { value: mintCost });
    await nft.approve(marketV1.target, 1n);

    // V1 同样使用原生 NFTListed 事件
    await expect(marketV1.listNFT(nft.target, 1n, salePrice))
      .to.emit(marketV1, "NFTListed")
      .withArgs(1n, sellerAddr, nft.target, 1n, salePrice);

    const buyer = await ethers.provider.getSigner(1);
    await marketV1.connect(buyer).buyNFT(1n, { value: salePrice });

    expect(await nft.ownerOf(1n)).to.equal(await buyer.getAddress());
  });
});