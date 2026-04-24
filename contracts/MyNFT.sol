// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyNFT
 * @dev ERC721标准NFT合约，支持铸造、元数据、供应量控制
 */
contract MyNFT is ERC721, ERC721URIStorage, Ownable {
    /// @dev TokenID 自增计数器
    uint256 private _tokenIdCounter;

    /// @dev 最大供应量
    uint256 public constant MAX_SUPPLY = 10000;

    /// @dev 铸造价格
    uint256 public mintPrice = 0.01 ether;

    /// @dev 铸造事件
    event NFTMinted(address indexed minter, uint256 indexed tokenId, string uri);

    constructor() ERC721("MyNFT", "MNFT") Ownable(msg.sender) {}

    /**
     * @dev 铸造NFT
     * @param uri 元数据地址
     */
    function mint(string memory uri) public payable returns (uint256) {
        require(_tokenIdCounter < MAX_SUPPLY, "Max supply reached");
        require(msg.value >= mintPrice, "Insufficient payment");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, uri);

        emit NFTMinted(msg.sender, newTokenId, uri);
        return newTokenId;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev 已铸造数量
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /// @dev 提取ETH
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }

    /// @dev 设置铸造价格
    function setMintPrice(uint256 newPrice) public onlyOwner {
        mintPrice = newPrice;
    }
}