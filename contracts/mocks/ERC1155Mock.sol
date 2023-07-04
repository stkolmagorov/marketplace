// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

import "../interfaces/IRoyaltySplitter.sol";

contract ERC1155Mock is IRoyaltySplitter, ERC1155, ERC2981 {
    address payable[] royaltyRecipients;
    uint256[] royaltyPercentages;

    error InvalidSumOfRoyaltyPercentages();

    constructor(address payable[] memory royaltyRecipients_, uint256[] memory royaltyPercentages_) ERC1155("Mock") {
        uint256 percentagesSum;
        for (uint256 i = 0; i < royaltyPercentages_.length; i++) {
            percentagesSum += royaltyPercentages_[i];
        }
        if (percentagesSum > 5000) {
            revert InvalidSumOfRoyaltyPercentages();
        }
        for (uint256 i = 0; i < 10; i++) {
            _mint(msg.sender, i, 100_000_000 ether, "");
        }
        royaltyRecipients = royaltyRecipients_;
        royaltyPercentages = royaltyPercentages_;
    }

    function getRoyalties(uint256) external view returns (address payable[] memory, uint256[] memory) {
        return (royaltyRecipients, royaltyPercentages);
    }

    function getNumOfRoyaltyReceivers(uint256) external view returns (uint256) {
        return royaltyRecipients.length;
    }

    function supportsInterface(bytes4 interfaceId_) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId_) || interfaceId_ == type(IRoyaltySplitter).interfaceId;
    }
}