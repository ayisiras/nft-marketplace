// MyNFT 合约单元测试
import { expect } from "chai";
import { network } from "hardhat";

// 初始化新版EDR ethers实例
const { ethers } = await network.create();

describe("MyNFT 合约测试", function () {
  // 测试用元数据
  const testURI = "ipfs://demo-nft-001";

  it("1. 合约部署成功，名称与符号匹配", async function () {
    const myNFT = await ethers.deployContract("MyNFT");
    expect(await myNFT.name()).to.equal("MyNFT");
    expect(await myNFT.symbol()).to.equal("MNFT");
    
  });

  it("2. 铸造NFT，正确触发 NFTMinted 事件", async function () {
    const myNFT = await ethers.deployContract("MyNFT");
    const signer = await ethers.provider.getSigner();
    const userAddr = await signer.getAddress();

    // 支付0.01ETH铸造
    await expect(myNFT.mint(testURI, { value: ethers.parseEther("0.01") }))
      .to.emit(myNFT, "NFTMinted")
      .withArgs(userAddr, 1n, testURI);
      //tokenURI 函数返回值正确
      expect(await myNFT.tokenURI(1)).to.equal(testURI);
      //supportsInterface 函数正确返回ERC165接口支持  
      const ERC165InterfaceId = "0x01ffc9a7";
      expect(await myNFT.supportsInterface(ERC165InterfaceId)).to.be.true;
    
    
      
  });

  it("3. 铸造NFT，未正确触发 Insufficient payment", async function () {
    const myNFT = await ethers.deployContract("MyNFT");
    const signer = await ethers.provider.getSigner();
    const userAddr = await signer.getAddress();
    // 函数调用后铸造价格为0.01ETH
    await myNFT.setMintPrice(ethers.parseEther("0.01"));
    // 支付不足铸造失败
    await expect(myNFT.mint(testURI, { value: ethers.parseEther("0.005") })).to.be.revertedWith("Insufficient payment");

  });

  it("4. 批量铸造，事件数量与总发行量一致", async function () {
    const myNFT = await ethers.deployContract("MyNFT");
    const startBlock = await ethers.provider.getBlockNumber();

    // 批量铸造3个NFT
    for (let i = 1; i <= 3; i++) {
      await myNFT.mint(`ipfs://nft-${i}`, { value: ethers.parseEther("0.01") });
    }

    // 过滤所有铸造事件
    const mintEvents = await myNFT.queryFilter(
      myNFT.filters.NFTMinted(),
      startBlock,
      "latest"
    );

    // 校验总量
    expect(await myNFT.totalSupply()).to.equal(BigInt(mintEvents.length));
    // withdraw 函数调用后合约余额为0
    await myNFT.withdraw();
    const contractBalance = await ethers.provider.getBalance(myNFT.target);
    expect(contractBalance).to.equal(0n);
   
  });
});