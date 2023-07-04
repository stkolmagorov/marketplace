// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface IMarketplaceV1 {
    enum Status { NONEXISTENT, ACTIVE, CANCELLED, CLOSED }

    enum AuctionType { COMMON, EBAY }

    struct CommissionRecipient {
        address payable commissionRecipientAddress;
        uint256 commissionRecipientPercentage;
    }

    struct SaleInfo {
        address payable seller;
        address paymentCurrency;
        address token;
        uint256 tokenId;
        uint256 availableAmountToPurchase;
        uint256 purchasedAmount;
        uint256 pricePerToken;
        bool isERC721;
        bool isRoyaltySupported;
        Status status;
    }

    struct AuctionInfo {
        address payable seller;
        address winner;
        address paymentCurrency;
        address token;
        uint256 tokenId;
        uint256 winningBid;
        uint256 amountToSale;
        uint256 redemptionPrice;
        bool isERC721;
        bool isRoyaltySupported;
        Status status;
        AuctionType auctionType;
    }

    error MaximumCommissionPercentageWasExceeded(uint256 commissionPercentage);
    error ZeroAddressEntry();
    error InvalidAuthorizer();
    error InvalidArrayLengths();
    error InvalidAmountOfTokensToSale();
    error UnsupportedCurrencyEntry(address unsupportedCurrency);
    error InvalidCallee();
    error InvalidStatus(Status status);
    error InvalidApprovedPricePerToken();
    error InvalidAmountOfTokensToPurchase();
    error InvalidRedemptionPrice();
    error NotUniqueSignature(bytes notUniqueSignature);
    error InvalidSignature(bytes invalidSignature);
    error InvalidAuctionTypeForRedemption(uint256 auctionId);
    error InvalidPercentagesSum();

    event CommissionPercentageWasUpdated(uint256 indexed newCommissionPercentage);
    event SupportedCurrenciesWereAdded(address[] indexed currencies);
    event SupportedCurrenciesWereRemoved(address[] indexed currencies);
    event AuthorizerWasUpdated(address indexed newAuthorizer);
    event SaleWasCreated(address indexed seller, uint256 indexed saleId);
    event SaleWasCancelled(uint256 indexed saleId);
    event SaleWasResolved(
        address[] indexed approvedBuyers, 
        uint256[] indexed approvedPricesPerToken, 
        uint256 indexed saleId
    );
    event PaymentForSaleWasProcessed(address indexed payer, uint256 indexed paymentAmount, uint256 indexed saleId);
    event AuctionWasCreated(address indexed owner, uint256 indexed auctionId);
    event AuctionWasCancelled(uint256 indexed auctionId);
    event AuctionWasResolved(address indexed winner, uint256 indexed winningBid, uint256 indexed auctionId);
    event PaymentForAuctionWasProcessed(address indexed payer, uint256 indexed paymentAmount, uint256 indexed auctionId);
    event CommissionRecipientsWereUpdated(
        address payable[] indexed newCommissionRecipientAddresses, 
        uint256[] indexed newCommissionRecipientPercentages
    );
}