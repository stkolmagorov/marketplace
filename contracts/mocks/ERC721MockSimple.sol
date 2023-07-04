// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721MockSimple is ERC721 {
    constructor() ERC721("Mock", "MOCK") {
        for (uint256 i = 0; i < 10; i++) {
            _safeMint(msg.sender, i);
        }
    }

    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return super.supportsInterface(interfaceId_);
    }
}