#ERC721Contract.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MyNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    constructor() ERC721("MyNFT", "MNFT") Ownable(msg.sender) {}

    /// @notice Mint a new NFT to the caller (only owner)
    function mint() public onlyOwner {
        _safeMint(msg.sender, _nextTokenId++);
    }
}
