// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract ERC721Mock is ERC721, ERC2981 {
    constructor(address royaltyRecipient_) ERC721("Mock", "MOCK") {
        for (uint256 i = 0; i < 10; i++) {
            _safeMint(msg.sender, i);
            _setTokenRoyalty(i, royaltyRecipient_, 1000);
        }
    }

    function supportsInterface(bytes4 interfaceId_) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId_);
    }
}