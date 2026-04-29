##项目目录
```bash
nft-marketplace/
├── contracts/
│ ├── MyNFT.sol # NFT 基础合约（无升级）
│ ├── NFTMarketplace.sol # 旧版 NFT 市场合约
│ └── NFTMarketplaceV1.sol # V1 升级版市场合约（接口兼容）
├── test/
│ ├── MyNFT.test.ts # NFT 合约测试
│ └── NFTMarketplace.test.ts # 市场旧版 → V1 升级流程测试
├── scripts/
│ ├── deploy-local.ts # 本地一键部署（全部合约）
│ └── deploy-sepolia.ts # Sepolia 测试网部署
├── hardhat.config.ts # Hardhat 配置（支持 .env）
├── .env # 环境变量（RPC / 私钥）
├── package.json # 项目依赖
└── README.md # 项目说明文档
```
## 🧩 合约功能说明
### 1. MyNFT.sol
- 标准 ERC721 NFT
- 支持铸造、设置价格、提取 ETH
- 最大发行量：10,000 枚
- 铸造单价：0.01 ETH

### 2. NFTMarketplace.sol（旧版）
- NFT 上架
- NFT 购买（buyNFT）
- 防重入安全机制

### 3. NFTMarketplaceV1.sol（升级版）
- 与旧版 **完全接口兼容**
- 统一使用 `buyNFT()`
- 优化结构，保持功能一致

---

## 🧪 实际测试数据（真实运行数据）
所有测试均使用以下固定数据，可复现、可验证：

### 固定测试参数
- NFT 铸造价格：**0.01 ETH**
- 市场挂单价格：**0.1 ETH**
- 测试 NFT 元数据 URI：`ipfs://demo-nft-001`
- 测试铸造数量：3 个
- 测试账户：卖家(0)、买家(1)

### 测试覆盖场景
1. NFT 名称、符号校验
2. 铸造 NFT 并触发 `NFTMinted` 事件
3. 批量铸造 → 事件数量 = 发行量
4. 旧版市场：上架 → 购买 → 所有权转移
5. V1 升级版：上架 → 购买（统一 buyNFT）
6. 合约事件：`NFTListed`、`NFTSold` 正确触发




## 1. 安装依赖和初始化
```bash
    //初始化npm
    npm init -y
    //安装hardhat3
    npm install --save-dev hardhat@latest
    npx hardhat --init
    npm install @openzeppelin/contracts
    npm install @chainlink/contracts
    npm install --save-dev @nomicfoundation/hardhat-ethers-chai-matchers
```
## 2.编译合约
```bash
运行
npx hardhat compile
```
## 3. 运行测试（全覆盖 + 实际业务数据）
实测测试用例数据
NFT 铸造费用：0.01 ETH
市场挂单售价：0.1 ETH
测试 NFT 元数据：ipfs://demo-nft-001
覆盖场景：铸造、事件校验、授权、上架、购买、所有权转移
执行命令：
```bash
运行
npx hardhat test
```
## 3.1 生成覆盖率报告
npx hardhat test --coverage
# 只运行Mocha测试并生成覆盖率
npx hardhat test mocha --coverage

## 4. 部署
4.1 本地全量部署（旧版 + 新版）
```bash
运行
npm run deploy:local
```
## 4.2 Sepolia 测试网部署
填写 .env 内 RPC 与私钥
执行：
```bash
运行
npm run deploy:sepolia
```
##  项目升级说明
MyNFT：无升级，作为底层资源合约
NFTMarketplace：初代旧版市场
NFTMarketplaceV1：迭代升级版，逻辑优化，接口完全向下兼容
##  核心交互函数
mint()：铸造 NFT
listNFT()：NFT 上架
buyNFT()：购买 NFT（新旧市场统一）

