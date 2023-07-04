// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface IRoyaltySplitter {
    function getRoyalties(uint256 tokenId) external view returns (address payable[] memory, uint256[] memory);
    function getNumOfRoyaltyReceivers(uint256 tokenId) external view returns (uint256);
}