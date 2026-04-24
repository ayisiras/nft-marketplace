// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入旧版合约（继承）
import "./NFTMarketplace.sol";
// ERC20标准与安全转账
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// 【已修正】Chainlink价格预言机导入路径
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title NFTMarketplaceV1
 * @dev 升级版本：支持ETH+ERC20出价 + Chainlink美元价格
 * @dev 透明代理非UUPS升级，方法名与旧版完全一致
 * @dev 存储100%兼容，不破坏旧版数据
 */
contract NFTMarketplaceV1 is NFTMarketplace {
    using SafeERC20 for IERC20;

    // ====================== V1新增状态变量（安全追加） ======================
    /// @dev Chainlink ETH/USD价格预言机
    AggregatorV3Interface public ethUsdPriceFeed;
    /// @dev 代币 => Chainlink价格预言机地址
    mapping(address => address) public tokenPriceFeeds;
    /// @dev ERC20待退款：拍卖ID => 用户 => 金额
    mapping(uint256 => mapping(address => uint256)) public pendingERC20Returns;
    /// @dev 拍卖对应的支付币种（ETH/ERC20）
    mapping(uint256 => address) public auctionBidToken;

    // ====================== 常量定义 ======================
    /// @dev ETH标识地址
    address public constant ETH_ADDRESS = address(0);

    // ====================== 新增事件 ======================
    /// @dev 代币价格预言机设置事件
    event PriceFeedSet(address indexed token, address indexed feed);

    /**
     * @dev 构造函数：禁用初始化，适配代理模式
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev V1升级初始化：仅管理员调用一次
     * @param _ethUsdFeed ETH/USD预言机地址
     */
    function initializeV1(address _ethUsdFeed) external onlyAdmin initializer {
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdFeed);
    }

    // ====================== 重写旧版方法（方法名完全一致） ======================

    /**
     * @dev 重写：创建拍卖（默认ETH支付）
     * @param nftContract NFT合约
     * @param tokenId NFT ID
     * @param startPrice 起拍价
     * @param durationHours 时长
     * @return 拍卖ID
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 durationHours
    ) external override returns (uint256) {
        return createAuction(nftContract, tokenId, startPrice, durationHours, ETH_ADDRESS);
    }

    /**
     * @dev 重载：创建拍卖（支持指定ERC20/ETH）方法名不变
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 durationHours,
        address bidToken
    ) public returns (uint256) {
        require(startPrice > 0, "Price >0");
        require(durationHours >=1, "Min 1h");
        
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(nft.isApprovedForAll(msg.sender, address(this)), "Not approved");

        // 自增拍卖ID
        auctionCounter++;
        Auction storage a = auctions[auctionCounter];
        
        // 赋值拍卖信息
        a.seller = msg.sender;
        a.nftContract = nftContract;
        a.tokenId = tokenId;
        a.startPrice = startPrice;
        a.highestBid = 0;
        a.highestBidder = address(0);
        a.endTime = block.timestamp + durationHours * 1 hours;
        a.active = true;

        // 记录支付币种
        auctionBidToken[auctionCounter] = bidToken;

        emit AuctionCreated(auctionCounter, msg.sender, nftContract, tokenId, startPrice, a.endTime);
        return auctionCounter;
    }

    /**
     * @dev 重写：ETH出价（方法名不变）
     */
    function placeBid(uint256 auctionId) external payable override nonReentrant {
        _placeBid(auctionId, ETH_ADDRESS, msg.value);
    }

    /**
     * @dev 重载：ERC20出价（方法名不变）
     */
    function placeBid(uint256 auctionId, address token, uint256 amount) external nonReentrant {
        _placeBid(auctionId, token, amount);
    }

    /**
     * @dev 内部出价逻辑
     */
    function _placeBid(uint256 aid, address token, uint256 amt) internal {
        Auction storage a = auctions[aid];
        require(a.active, "Inactive");
        require(block.timestamp < a.endTime, "Ended");
        require(auctionBidToken[aid] == token, "Wrong token");

        // 最低出价规则：高于上一出价5%
        uint256 minBid = a.highestBid == 0 ? a.startPrice : (a.highestBid * 105)/100;
        require(amt >= minBid, "Bid too low");

        // 旧出价人退款
        if (a.highestBidder != address(0)) {
            if (token == ETH_ADDRESS) {
                pendingReturns[aid][a.highestBidder] += a.highestBid;
            } else {
                pendingERC20Returns[aid][a.highestBidder] += a.highestBid;
            }
        }

        // ERC20代币转入合约
        if (token != ETH_ADDRESS) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amt);
        }

        // 更新最高出价
        a.highestBid = amt;
        a.highestBidder = msg.sender;
        emit BidPlaced(aid, msg.sender, amt);
    }

    /**
     * @dev 重写：ETH购买NFT（方法名不变）
     */
    function buyNFT(uint256 listingId) external payable override nonReentrant {
        _buyNFT(listingId, ETH_ADDRESS, msg.value);
    }

    /**
     * @dev 重载：ERC20购买NFT（方法名不变）
     */
    function buyNFT(uint256 listingId, address token, uint256 amount) external nonReentrant {
        _buyNFT(listingId, token, amount);
    }

    /**
     * @dev 内部统一购买逻辑
     */
    function _buyNFT(uint256 id, address token, uint256 amt) internal {
        Listing storage l = listings[id];
        require(l.active, "Inactive");
        require(amt >= l.price, "Insufficient amount");
        require(msg.sender != l.seller, "Cannot buy own");

        // 关闭挂单
        l.active = false;

        // 计算手续费
        uint256 fee = (l.price * platformFee) / 10000;
        uint256 sellerAmount = l.price - fee;

        // 转移NFT
        IERC721(l.nftContract).safeTransferFrom(l.seller, msg.sender, l.tokenId);

        // ETH支付
        if (token == ETH_ADDRESS) {
            (bool s,) = l.seller.call{value: sellerAmount}("");
            (bool f,) = feeRecipient.call{value: fee}("");
            require(s && f, "Transfer failed");
        } 
        // ERC20支付
        else {
            IERC20(token).safeTransferFrom(msg.sender, l.seller, sellerAmount);
            IERC20(token).safeTransferFrom(msg.sender, feeRecipient, fee);
        }

        emit NFTSold(id, msg.sender, l.seller, l.price);
    }

    /**
     * @dev 重写：结束拍卖（方法名不变）
     */
    function endAuction(uint256 auctionId) external override nonReentrant {
        Auction storage a = auctions[auctionId];
        require(a.active, "Inactive");
        require(block.timestamp >= a.endTime, "Not ended");

        // 关闭拍卖
        a.active = false;
        address payToken = auctionBidToken[auctionId];
        address winner = a.highestBidder;
        uint256 finalBid = a.highestBid;

        if (winner != address(0)) {
            uint256 fee = (finalBid * platformFee) / 10000;
            uint256 sellerAmount = finalBid - fee;

            // 转移NFT给赢家
            IERC721(a.nftContract).safeTransferFrom(a.seller, winner, a.tokenId);

            // ETH结算
            if (payToken == ETH_ADDRESS) {
                (bool s,) = a.seller.call{value: sellerAmount}("");
                (bool f,) = feeRecipient.call{value: fee}("");
                require(s && f, "Transfer failed");
            }
            // ERC20结算
            else {
                IERC20(payToken).safeTransfer(a.seller, sellerAmount);
                IERC20(payToken).safeTransfer(feeRecipient, fee);
            }
        }

        emit AuctionEnded(auctionId, winner, finalBid);
    }

    /**
     * @dev 重写：统一退款提取（ETH/ERC20自动识别）
     */
    function withdrawBid(uint256 auctionId) external override nonReentrant {
        address token = auctionBidToken[auctionId];

        // ETH退款
        if (token == ETH_ADDRESS) {
            uint256 amt = pendingReturns[auctionId][msg.sender];
            require(amt > 0, "No funds");
            pendingReturns[auctionId][msg.sender] = 0;
            (bool ok,) = msg.sender.call{value: amt}("");
            require(ok, "Failed");
        }
        // ERC20退款
        else {
            uint256 amt = pendingERC20Returns[auctionId][msg.sender];
            require(amt > 0, "No funds");
            pendingERC20Returns[auctionId][msg.sender] = 0;
            IERC20(token).safeTransfer(msg.sender, amt);
        }

        emit BidWithdrawn(msg.sender, auctionId, 0);
    }

    // ====================== Chainlink 价格工具 ======================
    /**
     * @dev 获取代币对应的美元价值
     * @param token 代币地址
     * @param amount 代币数量
     * @return usdValue 美元价值
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        (, int256 price,,,) = token == ETH_ADDRESS
            ? ethUsdPriceFeed.latestRoundData()
            : AggregatorV3Interface(tokenPriceFeeds[token]).latestRoundData();
        
        require(price > 0, "Invalid price");
        return uint256(price) * amount / 1e8;
    }

    /**
     * @dev 设置代币的Chainlink预言机
     * @param token 代币地址
     * @param feed 预言机地址
     */
    function setTokenPriceFeed(address token, address feed) external onlyAdmin {
        require(feed != address(0), "Invalid feed");
        tokenPriceFeeds[token] = feed;
        emit PriceFeedSet(token, feed);
    }
}