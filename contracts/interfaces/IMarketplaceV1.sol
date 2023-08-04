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

    event CommissionPercentageWasUpdated(uint256 indexed oldCommissionPercentage, uint256 indexed newCommissionPercentage);
    event SupportedCurrenciesWereAdded(address[] indexed currencies);
    event SupportedCurrenciesWereRemoved(address[] indexed currencies);
    event AuthorizerWasUpdated(address indexed oldAuthorizer, address indexed newAuthorizer);
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
        CommissionRecipient[] indexed oldCommissionRecipients,
        CommissionRecipient[] indexed newCommissionRecipients
    );

    /// @notice Initializes the contract.
    /// @param commissionRecipientAddresses Commission recipient addresses.
    /// @param commissionRecipientPercentages Commission recipient percentages.
    /// @param supportedCurrencies Supported currency addresses.
    /// @param authorizer Authorizer address.
    /// @param commissionPercentage Commission percentage.
    function initialize(
        address payable[] calldata commissionRecipientAddresses, 
        uint256[] calldata commissionRecipientPercentages,
        address[] calldata supportedCurrencies,
        address authorizer,
        uint256 commissionPercentage
    )
        external;

    /// @notice Updates commission recipient addresses and percentages.
    /// @param commissionRecipientAddresses Commission recipient addresses.
    /// @param commissionRecipientPercentages Commission recipient percentages.
    function updateCommissionRecipients(
        address payable[] calldata commissionRecipientAddresses, 
        uint256[] calldata commissionRecipientPercentages
    )
        external;

    /// @notice Updates the commission percentage.
    /// @param commissionPercentage New commission percentage value.
    function updateCommissionPercentage(uint256 commissionPercentage) external;

    /// @notice Updates the authorizer.
    /// @param authorizer New authorizer address.
    function updateAuthorizer(address authorizer) external;

    /// @notice Adds currencies to the list of supported currencies.
    /// @param currencies Currency addresses.
    function addSupportedCurrencies(address[] calldata currencies) external;

    /// @notice Removes currencies from the list of supported currencies.
    /// @param currencies Currency addresses.
    function removeSupportedCurrencies(address[] calldata currencies) external;

    /// @notice Creates sales.
    /// @param paymentCurrencies Payment currency addresses 
    /// (should be zero if the payment is supposed to be made in native currency).
    /// @param tokens Token addresses (ERC721 or ERC1155).
    /// @param tokenIds Token ids.
    /// @param amountsToSale Amounts of tokens to sale.
    /// @param pricesPerToken Prices per token.
    /// @param isERC721 Array of boolean values defining which token standard is being sold.
    function createSales(
        address[] calldata paymentCurrencies,
        address[] calldata tokens,
        uint256[] calldata tokenIds,
        uint256[] calldata amountsToSale,
        uint256[] calldata pricesPerToken,
        bool[] calldata isERC721
    )
        external;

    /// @notice Cancels sales.
    /// @param saleIds Sale ids.
    function cancelSales(uint256[] calldata saleIds) external;

    /// @notice Accepts bids on price for sale.
    /// @param approvedBuyers Approved buyer addresses.
    /// @param approvedPricesPerToken Approved prices per token.
    /// @param signature Signature to verify the caller's permissions.
    /// @param saleId Sale id.
    function resolveSale(
        address[] calldata approvedBuyers, 
        uint256[] calldata approvedPricesPerToken,
        bytes calldata signature,
        uint256 saleId
    )
        external;

    /// @notice Processes sales payments.
    /// @param saleIds Sale ids.
    /// @param amountsToPurchase Amounts of tokens to purchase.
    function processPaymentsForSales(
        uint256[] calldata saleIds, 
        uint256[] calldata amountsToPurchase
    ) 
        external 
        payable;
    
    /// @notice Creates auctions.
    /// @param paymentCurrencies Payment currency addresses 
    /// (should be zero if the payment is supposed to be made in native currency).
    /// @param tokens Token addresses (ERC721 or ERC1155).
    /// @param tokenIds Token ids.
    /// @param amountsToSale Amounts of tokens to sale.
    /// @param redemptionPrices Instant redemption prices.
    /// @param isERC721 Array of boolean values defining which token standard is being sold.
    /// @param auctionTypes Auction types.
    function createAuctions(
        address[] calldata paymentCurrencies,
        address[] calldata tokens,
        uint256[] calldata tokenIds,
        uint256[] calldata amountsToSale,
        uint256[] calldata redemptionPrices,
        bool[] memory isERC721,
        AuctionType[] memory auctionTypes
    )
        external;

    /// @notice Cancels auctions.
    /// @param auctionIds Auction ids.
    function cancelAuctions(uint256[] calldata auctionIds) external;

    /// @notice Determines the winners of auctions.
    /// @param winners Auction winner addresses.
    /// @param winningBids Winning bids.
    /// @param auctionIds Auction ids.
    /// @param signatures Signatures to verify the caller's permissions.
    function resolveAuctions(
        address[] calldata winners, 
        uint256[] calldata winningBids, 
        uint256[] calldata auctionIds,
        bytes[] calldata signatures
    ) 
        external;

    /// @notice Processes auction payments.
    /// @param auctionIds Auction ids.
    /// @param isRedemption Array of boolean values defining whether the caller wants to redeem auction.
    function processPaymentsForAuctions(
        uint256[] calldata auctionIds,
        bool[] calldata isRedemption
    )   
        external 
        payable;
    
    /// @notice Retrieves the current sale id value.
    /// @return Current sale id value.
    function currentSaleId() external view returns (uint256);

    /// @notice Retrieves the current auction id value.
    /// @return Current auction id value.
    function currentAuctionId() external view returns (uint256);
}