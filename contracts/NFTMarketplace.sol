// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入依赖库：ERC721标准接口、NFT接收接口、重入防护、代理初始化
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title NFTMarketplace
 * @dev NFT交易市场初始版本，支持NFT上架、购买、拍卖
 * @dev 采用透明代理模式，可升级，继承重入防护与NFT接收标准
 * @author 定制版合约
 */
contract NFTMarketplace is ReentrancyGuard, IERC721Receiver, Initializable {
    /**
     * @dev NFT挂单结构体：存储单个NFT的上架信息
     * @param seller 卖家钱包地址
     * @param nftContract NFT合约地址
     * @param tokenId NFT唯一ID
     * @param price 出售价格(ETH)
     * @param active 挂单是否有效
     */
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    /**
     * @dev NFT拍卖结构体：存储拍卖全量信息
     * @param seller 拍卖发起人/卖家
     * @param nftContract NFT合约地址
     * @param tokenId NFT唯一ID
     * @param startPrice 拍卖起拍价
     * @param highestBid 当前最高出价
     * @param highestBidder 最高出价人地址
     * @param endTime 拍卖结束时间戳
     * @param active 拍卖是否有效
     */
    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startPrice;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        bool active;
    }

    // ====================== 全局状态变量 ======================
    /// @dev 挂单ID => 挂单信息
    mapping(uint256 => Listing) public listings;
    /// @dev 挂单自增计数器
    uint256 public listingCounter;
    /// @dev 拍卖ID => 拍卖信息
    mapping(uint256 => Auction) public auctions;
    /// @dev 拍卖自增计数器
    uint256 public auctionCounter;
    /// @dev 拍卖待退款：拍卖ID => 用户地址 => 可退款金额
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;
    /// @dev 平台手续费，万分之几(250=2.5%)
    uint256 public platformFee;
    /// @dev 手续费接收地址
    address public feeRecipient;
    /// @dev 合约管理员(代理升级/配置权限)
    address public admin;

    // ====================== 事件定义 ======================
    /// @dev NFT上架成功事件
    event NFTListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
    /// @dev NFT下架成功事件
    event NFTDelisted(uint256 indexed listingId);
    /// @dev 挂单价格修改事件
    event PriceUpdated(uint256 indexed listingId, uint256 newPrice);
    /// @dev NFT购买成功事件
    event NFTSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);
    /// @dev 拍卖创建事件
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 startPrice, uint256 endTime);
    /// @dev 拍卖出价事件
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    /// @dev 拍卖结束事件
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 finalPrice);
    /// @dev 出价退款提取事件
    event BidWithdrawn(address indexed bidder, uint256 indexed auctionId, uint256 amount);

    /**
     * @dev 构造函数：禁用初始化为代理模式做准备
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 代理初始化函数：仅执行一次
     * @param _feeRecipient 平台手续费接收地址
     */
    function initialize(address _feeRecipient) external initializer {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        platformFee = 250;
        feeRecipient = _feeRecipient;
        admin = msg.sender;
    }

    /**
     * @dev 管理员权限修饰器：仅管理员可调用
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    /**
     * @dev 标准ERC721接收方法：合约必须实现才能接收NFT
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev 用户上架NFT
     * @param nftContract NFT合约地址
     * @param tokenId NFT ID
     * @param price 出售价格
     * @return 挂单ID
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external virtual returns (uint256) {
        require(price > 0, "Price > 0");
        require(nftContract != address(0), "Invalid NFT");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(
            nft.getApproved(tokenId) == address(this) ||
            nft.isApprovedForAll(msg.sender, address(this)),
            "Not approved"
        );

        listingCounter++;
        listings[listingCounter] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit NFTListed(listingCounter, msg.sender, nftContract, tokenId, price);
        return listingCounter;
    }

    /**
     * @dev 卖家主动下架NFT
     * @param listingId 挂单ID
     */
    function delistNFT(uint256 listingId) external virtual {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");
        listing.active = false;
        emit NFTDelisted(listingId);
    }

    /**
     * @dev 修改挂单价格
     * @param listingId 挂单ID
     * @param newPrice 新价格
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external virtual {
        require(newPrice > 0, "Price > 0");
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");
        listing.price = newPrice;
        emit PriceUpdated(listingId, newPrice);
    }

    /**
     * @dev 购买NFT（ETH支付）
     * @param listingId 挂单ID
     */
    function buyNFT(uint256 listingId) external payable virtual nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing inactive");
        require(msg.value >= listing.price, "Insufficient ETH");
        require(msg.sender != listing.seller, "Cannot buy own NFT");

        // 第一步：关闭挂单（防重入）
        listing.active = false;

        // 第二步：计算手续费与卖家收入
        uint256 fee = (listing.price * platformFee) / 10000;
        uint256 sellerProceed = listing.price - fee;
        uint256 refund = msg.value - listing.price;

        // 第三步：转移NFT
       IERC721(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);

        // 第四步：转账给卖家
        (bool sellerTransfer, ) = listing.seller.call{value: sellerProceed}("");
        require(sellerTransfer, "Seller transfer failed");

        // 第五步：转账手续费
        (bool feeTransfer, ) = feeRecipient.call{value: fee}("");
        require(feeTransfer, "Fee transfer failed");

        // 第六步：退还多余ETH
        if (refund > 0) {
            (bool refundTransfer, ) = msg.sender.call{value: refund}("");
            require(refundTransfer, "Refund failed");
        }

        emit NFTSold(listingId, msg.sender, listing.seller, listing.price);
    }

    /**
     * @dev 创建ETH拍卖
     * @param nftContract NFT合约
     * @param tokenId NFT ID
     * @param startPrice 起拍价
     * @param durationHours 拍卖时长(小时)
     * @return 拍卖ID
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 durationHours
    ) external virtual returns (uint256) {
        require(startPrice > 0, "Start price > 0");
        require(durationHours >= 1, "Min 1h");
        require(nftContract != address(0), "Invalid NFT");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(
            nft.getApproved(tokenId) == address(this) ||
            nft.isApprovedForAll(msg.sender, address(this)),
            "Not approved"
        );

        auctionCounter++;
        auctions[auctionCounter] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPrice: startPrice,
            highestBid: 0,
            highestBidder: address(0),
            endTime: block.timestamp + durationHours * 1 hours,
            active: true
        });
         // 转移NFT到合约
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        emit AuctionCreated(auctionCounter, msg.sender, nftContract, tokenId, startPrice, auctions[auctionCounter].endTime);
        return auctionCounter;
    }

    /**
     * @dev ETH出价
     * @param auctionId 拍卖ID
     */
    function placeBid(uint256 auctionId) external payable virtual nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction inactive");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.sender != auction.seller, "Seller can't bid");

        uint256 minBid = auction.highestBid == 0
            ? auction.startPrice
            : auction.highestBid * 105 / 100;
        require(msg.value >= minBid, "Bid too low");

        // 记录上一位出价人退款
        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder] += auction.highestBid;
        }

        // 更新最高出价
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /**
     * @dev 提取拍卖退款
     * @param auctionId 拍卖ID
     */
    function withdrawBid(uint256 auctionId) external virtual nonReentrant {
        uint256 amount = pendingReturns[auctionId][msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        // 清零金额（防重入）
        pendingReturns[auctionId][msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdraw failed");
        emit BidWithdrawn(msg.sender, auctionId, amount);
    }

    /**
     * @dev 结束拍卖
     * @param auctionId 拍卖ID
     */
    function endAuction(uint256 auctionId) external virtual nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction inactive");
        require(block.timestamp >= auction.endTime, "Not ended");

        auction.active = false;
        address winner = auction.highestBidder;
        uint256 finalBid = auction.highestBid;

        if (winner != address(0)) {
            uint256 fee = (finalBid * platformFee) / 10000;
            uint256 sellerProceed = finalBid - fee;

            // 转移NFT给赢家
			IERC721(auction.nftContract).safeTransferFrom(address(this), winner,auction.tokenId);
            (bool s1, ) = auction.seller.call{value: sellerProceed}("");
            require(s1, "Seller failed");

            (bool s2, ) = feeRecipient.call{value: fee}("");
            require(s2, "Fee failed");
        }

        delete pendingReturns[auctionId][auction.highestBidder];
        emit AuctionEnded(auctionId, winner, finalBid);
    }

    /**
     * @dev 设置平台手续费
     * @param newFee 新手续费
     */
    function setPlatformFee(uint256 newFee) external virtual {
        require(msg.sender == feeRecipient, "Not fee owner");
        require(newFee <= 1000, "Max 10%");
        platformFee = newFee;
    }

    /**
     * @dev 修改手续费接收地址
     * @param newRecipient 新地址
     */
    function updateFeeRecipient(address newRecipient) external virtual {
        require(msg.sender == feeRecipient, "Not fee owner");
        require(newRecipient != address(0), "Invalid address");
        feeRecipient = newRecipient;
    }
}