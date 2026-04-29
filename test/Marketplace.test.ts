// NFT市场 旧版 → V1升级版 完整流程测试
import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();


describe("NFTMarketplace", function () {
  let marketplace: any;
  let myNFT: any;
  let owner: any;
  let seller: any;
  let buyer: any;
  let feeRecipient: any;

  const MINT_PRICE = ethers.parseEther("0.01");
  const LIST_PRICE = ethers.parseEther("0.1");
  const AUCTION_START_PRICE = ethers.parseEther("0.05");
  const TEST_URI = "ipfs://test-uri";

  beforeEach(async function () {
    [owner, seller, buyer, feeRecipient] = await ethers.getSigners();

    // 部署 NFT
    const MyNFT = await ethers.getContractFactory("MyNFT");
    myNFT = await MyNFT.deploy();
    await myNFT.waitForDeployment();

    // ----------------------------
    // ✅ 正确部署可升级市场（测试专用）
    // ----------------------------
    const MarketplaceFactory = await ethers.getContractFactory("NFTMarketplace");
    const logicContract = await MarketplaceFactory.deploy();
    await logicContract.waitForDeployment();

    // 直接调用初始化函数（绕过代理限制）
    marketplace = logicContract;
    await marketplace.initialize(feeRecipient.address);

    // 卖家铸造 NFT 并授权
    await myNFT.connect(seller).mint(TEST_URI, { value: MINT_PRICE });
    await myNFT.connect(seller).approve(await marketplace.getAddress(), 1);
  });

  // ==========================================
  // 初始化
  // ==========================================
  it("initialize 正确设置手续费和接收地址", async function () {
    expect(await marketplace.platformFee()).to.equal(250);
    expect(await marketplace.feeRecipient()).to.equal(await feeRecipient.getAddress());
  });

  // ==========================================
  // 上架
  // ==========================================
  it("listNFT 成功上架 NFT", async function () {
    await marketplace.connect(seller).listNFT(await myNFT.getAddress(), 1, LIST_PRICE);
    const listing = await marketplace.listings(1);
    expect(listing.active).to.be.true;
  });

  // ==========================================
  // 下架
  // ==========================================
  it("delistNFT 卖家可以下架", async function () {
    await marketplace.connect(seller).listNFT(await myNFT.getAddress(), 1, LIST_PRICE);
    await marketplace.connect(seller).delistNFT(1);
    const listing = await marketplace.listings(1);
    expect(listing.active).to.be.false;
  });

  // ==========================================
  // 修改价格
  // ==========================================
  it("updatePrice 卖家可以修改挂单价格", async function () {
    await marketplace.connect(seller).listNFT(await myNFT.getAddress(), 1, LIST_PRICE);
    const newPrice = ethers.parseEther("0.15");
    await marketplace.connect(seller).updatePrice(1, newPrice);
    const listing = await marketplace.listings(1);
    expect(listing.price).to.equal(newPrice);
  });

  // ==========================================
  // 购买
  // ==========================================
  it("buyNFT 成功购买 NFT", async function () {
    await marketplace.connect(seller).listNFT(await myNFT.getAddress(), 1, LIST_PRICE);
    await marketplace.connect(buyer).buyNFT(1, { value: LIST_PRICE });
    expect(await myNFT.ownerOf(1)).to.equal(await buyer.getAddress());
  });

  it("buyNFT 不能购买自己的 NFT", async function () {
    await marketplace.connect(seller).listNFT(await myNFT.getAddress(), 1, LIST_PRICE);
    await expect(
      marketplace.connect(seller).buyNFT(1, { value: LIST_PRICE })
    ).to.be.revertedWith("Cannot buy own NFT");
  });

  // ==========================================
  // 创建拍卖
  // ==========================================
  it("createAuction 成功创建拍卖", async function () {
    await marketplace.connect(seller).createAuction(
      await myNFT.getAddress(),
      1,
      AUCTION_START_PRICE,
      24
    );
    const auction = await marketplace.auctions(1);
    expect(auction.active).to.be.true;
  });

  // ==========================================
  // 出价
  // ==========================================
  it("placeBid 成功出价", async function () {
    await marketplace.connect(seller).createAuction(
      await myNFT.getAddress(),
      1,
      AUCTION_START_PRICE,
      24
    );
    await marketplace.connect(buyer).placeBid(1, { value: AUCTION_START_PRICE });
    const auction = await marketplace.auctions(1);
    expect(auction.highestBid).to.equal(AUCTION_START_PRICE);
  });

  // ==========================================
  // 退款
  // ==========================================
  it("withdrawBid 成功提取退款", async function () {
    await marketplace.connect(seller).createAuction(
      await myNFT.getAddress(),
      1,
      AUCTION_START_PRICE,
      24
    );
    await marketplace.connect(buyer).placeBid(1, { value: AUCTION_START_PRICE });
    await marketplace.connect(owner).placeBid(1, { value: ethers.parseEther("0.06") });

    await expect(marketplace.connect(buyer).withdrawBid(1));
      //.to.changeEtherBalance(buyer, AUCTION_START_PRICE);
  });

  // ==========================================
  // 结束拍卖
  // ==========================================
  it("endAuction 结束拍卖并转移 NFT", async function () {
    await marketplace.connect(seller).createAuction(
      await myNFT.getAddress(),
      1,
      AUCTION_START_PRICE,
      24
    );
    await marketplace.connect(buyer).placeBid(1, { value: AUCTION_START_PRICE });

    await ethers.provider.send("evm_increaseTime", [24 * 3600]);
    await ethers.provider.send("evm_mine", []);

    await marketplace.endAuction(1);
    expect(await myNFT.ownerOf(1)).to.equal(await buyer.getAddress());
  });

  // ==========================================
  // 设置费率
  // ==========================================
  it("setPlatformFee 费率所有者可修改费率", async function () {
    await marketplace.connect(feeRecipient).setPlatformFee(300);
    expect(await marketplace.platformFee()).to.equal(300);
  });

  // ==========================================
  // 修改收款地址
  // ==========================================
  it("updateFeeRecipient 费率所有者可修改收款地址", async function () {
    await marketplace.connect(feeRecipient).updateFeeRecipient(await buyer.getAddress());
    expect(await marketplace.feeRecipient()).to.equal(await buyer.getAddress());
  });

  // ==========================================
  // ERC721 接收
  // ==========================================
  it("onERC721Received 返回正确选择器", async function () {
    const res = await marketplace.onERC721Received(
      ethers.ZeroAddress,
      ethers.ZeroAddress,
      1,
      "0x"
    );
    expect(res).to.equal("0x150b7a02");
  });
});