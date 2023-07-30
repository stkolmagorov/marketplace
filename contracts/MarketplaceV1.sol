// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";

import "./interfaces/IMarketplaceV1.sol";
import "./interfaces/IRoyaltySplitter.sol";

contract MarketplaceV1 is 
    IMarketplaceV1,
    UUPSUpgradeable, 
    ERC1155HolderUpgradeable, 
    ERC721HolderUpgradeable, 
    ReentrancyGuardUpgradeable, 
    AccessControlUpgradeable 
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using ECDSAUpgradeable for bytes32;
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant BASE_PERCENTAGE = 10000;
    uint256 public constant MAXIMUM_COMMISSION_PERCENTAGE = 1000;
    bytes32 public constant SALE_HASH = keccak256("SALE");
    bytes32 public constant AUCTION_HASH = keccak256("AUCTION");
    bytes4 public constant ERC_2981_INTERFACE_ID = type(IERC2981Upgradeable).interfaceId;
    bytes4 public constant ROYALTY_SPLITTER_INTERFACE_ID = type(IRoyaltySplitter).interfaceId;

    // V1
    address public authorizer;
    uint256 public commissionPercentage;
    CountersUpgradeable.Counter private _saleId;
    CountersUpgradeable.Counter private _auctionId;

    mapping(bytes => bool) public notUniqueSignature;
    mapping(address => bool) public isSupportedCurrency;
    mapping(uint256 => SaleInfo) public sales;
    mapping(uint256 => AuctionInfo) public auctions;
    mapping(uint256 => mapping(address => uint256)) public approvedPricePerTokenBySaleIdAndApprovedBuyer;
    CommissionRecipient[] public commissionRecipients;

    /// @notice Initializes the contract.
    /// @param commissionRecipientAddresses_ Commission recipient addresses.
    /// @param commissionRecipientPercentages_ Commission recipient percentages.
    /// @param supportedCurrencies_ Supported currency addresses.
    /// @param authorizer_ Authorizer address.
    /// @param commissionPercentage_ Commission percentage.
    function initialize(
        address payable[] calldata commissionRecipientAddresses_, 
        uint256[] calldata commissionRecipientPercentages_,
        address[] calldata supportedCurrencies_,
        address authorizer_,
        uint256 commissionPercentage_
    )
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __ERC1155Holder_init();
        __ERC721Holder_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        updateCommissionRecipients(commissionRecipientAddresses_, commissionRecipientPercentages_);
        addSupportedCurrencies(supportedCurrencies_);
        authorizer = authorizer_;
        commissionPercentage = commissionPercentage_;
        isSupportedCurrency[address(0)] = true;
    }

    /// @notice Updates the commission percentage.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param commissionPercentage_ New commission percentage value.
    function updateCommissionPercentage(
        uint256 commissionPercentage_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (commissionPercentage_ > MAXIMUM_COMMISSION_PERCENTAGE) {
            revert MaximumCommissionPercentageWasExceeded(commissionPercentage_);
        }
        emit CommissionPercentageWasUpdated(commissionPercentage, commissionPercentage_);
        commissionPercentage = commissionPercentage_;
    }

    /// @notice Updates the authorizer.
    /// @param authorizer_ New authorizer address.
    function updateAuthorizer(address authorizer_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit AuthorizerWasUpdated(authorizer, authorizer_);
        authorizer = authorizer_;
    }

    /// @notice Removes `currencies_` from the list of supported currencies. 
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param currencies_ Currency addresses.
    function removeSupportedCurrencies(
        address[] calldata currencies_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < currencies_.length; i++) {
            if (currencies_[i] == address(0)) {
                revert ZeroAddressEntry();
            }
            delete isSupportedCurrency[currencies_[i]];
        }
        emit SupportedCurrenciesWereRemoved(currencies_);
    }

    /// @notice Creates sales.
    /// @param paymentCurrencies_ Payment currency addresses 
    /// (should be zero if the payment is supposed to be made in native currency).
    /// @param tokens_ Token addresses (ERC721 or ERC1155).
    /// @param tokenIds_ Token ids.
    /// @param amountsToSale_ Amounts of tokens to sale.
    /// @param pricesPerToken_ Prices per token.
    /// @param isERC721_ Array of boolean values defining which token standard is being sold.
    function createSales(
        address[] calldata paymentCurrencies_,
        address[] calldata tokens_,
        uint256[] calldata tokenIds_,
        uint256[] calldata amountsToSale_,
        uint256[] calldata pricesPerToken_,
        bool[] calldata isERC721_
    )
        external
        onlyProxy
    {
        if (
            paymentCurrencies_.length != tokens_.length || 
            tokens_.length != tokenIds_.length ||
            tokenIds_.length != amountsToSale_.length ||
            amountsToSale_.length != pricesPerToken_.length ||
            pricesPerToken_.length != isERC721_.length
        ) {
            revert InvalidArrayLengths();
        }
        for (uint256 i = 0; i < tokens_.length; i++) {
            if (isERC721_[i] && amountsToSale_[i] != 1 || amountsToSale_[i] == 0) {
                revert InvalidAmountOfTokensToSale();
            }
            if (!isSupportedCurrency[paymentCurrencies_[i]]) {
                revert UnsupportedCurrencyEntry(paymentCurrencies_[i]);
            }
            if (isERC721_[i]) {
                IERC721Upgradeable(tokens_[i]).safeTransferFrom(
                    msg.sender, 
                    address(this), 
                    tokenIds_[i], 
                    ""
                );
            } else {
                IERC1155Upgradeable(tokens_[i]).safeTransferFrom(
                    msg.sender, 
                    address(this), 
                    tokenIds_[i], 
                    amountsToSale_[i], 
                    ""
                );
            }
            uint256 saleId = _saleId.current();
            sales[saleId] = SaleInfo(
                payable(msg.sender),
                paymentCurrencies_[i],
                tokens_[i],
                tokenIds_[i],
                amountsToSale_[i],
                0,
                pricesPerToken_[i],
                isERC721_[i],
                IERC165Upgradeable(tokens_[i]).supportsInterface(ERC_2981_INTERFACE_ID),
                Status.ACTIVE
            );
            _saleId.increment();
            emit SaleWasCreated(msg.sender, saleId);
        }
    }

    /// @notice Cancels sales.
    /// @param saleIds_ Sale ids.
    function cancelSales(uint256[] calldata saleIds_) external nonReentrant onlyProxy {
        for (uint256 i = 0; i < saleIds_.length; i++) {
            SaleInfo storage saleInfo = sales[saleIds_[i]];
            if (msg.sender != saleInfo.seller) {
                revert InvalidCallee();
            }
            if (saleInfo.status != Status.ACTIVE) {
                revert InvalidStatus(saleInfo.status);
            }
            if (saleInfo.isERC721) {
                IERC721Upgradeable(saleInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    saleInfo.tokenId, 
                    ""
                );
            } else {
                IERC1155Upgradeable(saleInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    saleInfo.tokenId, 
                    saleInfo.availableAmountToPurchase, 
                    ""
                );
            }
            saleInfo.status = Status.CANCELLED;
            emit SaleWasCancelled(saleIds_[i]);
        }
    }

    /// @notice Accepts bids on price for sale.
    /// @param approvedBuyers_ Approved buyer addresses.
    /// @param approvedPricesPerToken_ Approved prices per token.
    /// @param signature_ Signature to verify the caller's permissions.
    /// @param saleId_ Sale id.
    function resolveSale(
        address[] calldata approvedBuyers_, 
        uint256[] calldata approvedPricesPerToken_,
        bytes calldata signature_,
        uint256 saleId_
    )
        external
        onlyProxy
    {
        if (approvedBuyers_.length != approvedPricesPerToken_.length) {
            revert InvalidArrayLengths();
        }
        if (notUniqueSignature[signature_]) {
            revert NotUniqueSignature(signature_);
        }
        bytes32 hash = keccak256(abi.encode(approvedBuyers_, approvedPricesPerToken_, saleId_, SALE_HASH));
        if (hash.toEthSignedMessageHash().recover(signature_) != authorizer) {
            revert InvalidSignature(signature_);
        }
        SaleInfo storage saleInfo = sales[saleId_];
        if (msg.sender != saleInfo.seller) {
            revert InvalidCallee();
        }
        if (saleInfo.status != Status.ACTIVE) {
            revert InvalidStatus(saleInfo.status);
        }
        for (uint256 i = 0; i < approvedBuyers_.length; i++) {
            if (approvedPricesPerToken_[i] == 0) {
                revert InvalidApprovedPricePerToken();
            }
            approvedPricePerTokenBySaleIdAndApprovedBuyer[saleId_][approvedBuyers_[i]] = approvedPricesPerToken_[i];
        }
        notUniqueSignature[signature_] = true;
        emit SaleWasResolved(approvedBuyers_, approvedPricesPerToken_, saleId_);
    }

    /// @notice Processes sales payments.
    /// @param saleIds_ Sale ids.
    /// @param amountsToPurchase_ Amounts of tokens to purchase.
    function processPaymentsForSales(
        uint256[] calldata saleIds_, 
        uint256[] calldata amountsToPurchase_
    ) 
        external 
        payable 
        nonReentrant 
        onlyProxy
    {
        if (saleIds_.length != amountsToPurchase_.length) {
            revert InvalidArrayLengths();
        }
        uint256 commissionPercentageMemory = commissionPercentage;
        CommissionRecipient[] memory commissionRecipientsMemory = commissionRecipients;
        uint256 msgValueSpent;
        for (uint256 i = 0; i < saleIds_.length; i++) {
            SaleInfo storage saleInfo = sales[saleIds_[i]];
            uint256 amountToPurchase = amountsToPurchase_[i];
            if (saleInfo.status != Status.ACTIVE) {
                revert InvalidStatus(saleInfo.status);
            }
            bool isERC721 = saleInfo.isERC721;
            if (isERC721 && amountToPurchase != 1 || amountToPurchase == 0) {
                revert InvalidAmountOfTokensToPurchase();
            }
            uint256 paymentAmount;
            uint256 approvedPrice = approvedPricePerTokenBySaleIdAndApprovedBuyer[saleIds_[i]][msg.sender];
            if (approvedPrice > 0) {
                paymentAmount = amountToPurchase * approvedPrice;
            } else {
                paymentAmount = amountToPurchase * saleInfo.pricePerToken;
            }
            msgValueSpent += _processPayment(
                commissionRecipientsMemory, 
                saleInfo.seller,
                saleInfo.paymentCurrency,
                saleInfo.token,
                saleInfo.tokenId,
                commissionPercentageMemory,
                paymentAmount,
                saleInfo.isRoyaltySupported
            );
            if (isERC721) {
                IERC721Upgradeable(saleInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender,
                    saleInfo.tokenId, 
                    ""
                );
            } else {
                IERC1155Upgradeable(saleInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    saleInfo.tokenId, 
                    amountToPurchase, 
                    ""
                );
            }
            saleInfo.availableAmountToPurchase -= amountToPurchase;
            if (saleInfo.availableAmountToPurchase == 0) {
                saleInfo.status = Status.CLOSED;
            }
            unchecked {
                saleInfo.purchasedAmount += amountToPurchase;
            }
            emit PaymentForSaleWasProcessed(msg.sender, paymentAmount, saleIds_[i]);
        }
        if (msg.value > msgValueSpent) {
            payable(msg.sender).sendValue(msg.value - msgValueSpent);
        }
    }

    /// @notice Creates auctions.
    /// @param paymentCurrencies_ Payment currency addresses 
    /// (should be zero if the payment is supposed to be made in native currency).
    /// @param tokens_ Token addresses (ERC721 or ERC1155).
    /// @param tokenIds_ Token ids.
    /// @param amountsToSale_ Amounts of tokens to sale.
    /// @param redemptionPrices_ Instant redemption prices.
    /// @param isERC721_ Array of boolean values defining which token standard is being sold.
    /// @param auctionTypes_ Auction types.
    function createAuctions(
        address[] calldata paymentCurrencies_,
        address[] calldata tokens_,
        uint256[] calldata tokenIds_,
        uint256[] calldata amountsToSale_,
        uint256[] calldata redemptionPrices_,
        bool[] memory isERC721_,
        AuctionType[] memory auctionTypes_
    )
        external
        onlyProxy
    {
        if (
            paymentCurrencies_.length != tokens_.length || 
            tokens_.length != tokenIds_.length ||
            tokenIds_.length != amountsToSale_.length ||
            amountsToSale_.length != redemptionPrices_.length ||
            redemptionPrices_.length != isERC721_.length ||
            isERC721_.length != auctionTypes_.length
        ) {
            revert InvalidArrayLengths();
        }
        for (uint256 i = 0; i < tokens_.length; i++) {
            if (isERC721_[i] && amountsToSale_[i] != 1 || amountsToSale_[i] == 0) {
                revert InvalidAmountOfTokensToSale();
            }
            if (!isSupportedCurrency[paymentCurrencies_[i]]) {
                revert UnsupportedCurrencyEntry(paymentCurrencies_[i]);
            }
            if (
                auctionTypes_[i] == AuctionType.COMMON && redemptionPrices_[i] > 0 ||
                auctionTypes_[i] == AuctionType.EBAY && redemptionPrices_[i] == 0
            ) {
                revert InvalidRedemptionPrice();
            }
            if (isERC721_[i]) {
                IERC721Upgradeable(tokens_[i]).safeTransferFrom(
                    msg.sender, 
                    address(this), 
                    tokenIds_[i], 
                    ""
                );
            } else {
                IERC1155Upgradeable(tokens_[i]).safeTransferFrom(
                    msg.sender, 
                    address(this), 
                    tokenIds_[i], 
                    amountsToSale_[i], 
                    ""
                );
            }
            uint256 auctionId = _auctionId.current();
            auctions[auctionId] = AuctionInfo(
                payable(msg.sender),
                address(0),
                paymentCurrencies_[i],
                tokens_[i],
                tokenIds_[i],
                0,
                amountsToSale_[i],
                redemptionPrices_[i],
                isERC721_[i],
                IERC165Upgradeable(tokens_[i]).supportsInterface(ERC_2981_INTERFACE_ID),
                Status.ACTIVE,
                auctionTypes_[i]
            );
            _auctionId.increment();
            emit AuctionWasCreated(msg.sender, auctionId);
        }
    }

    /// @notice Cancels auctions.
    /// @param auctionIds_ Auction ids.
    function cancelAuctions(uint256[] calldata auctionIds_) external nonReentrant onlyProxy {
        for (uint256 i = 0; i < auctionIds_.length; i++) {
            uint256 auctionId = auctionIds_[i];
            AuctionInfo storage auctionInfo = auctions[auctionId];
            if (msg.sender != auctionInfo.seller) {
                revert InvalidCallee();
            }
            if (auctionInfo.status != Status.ACTIVE) {
                revert InvalidStatus(auctionInfo.status);
            }
            if (auctionInfo.isERC721) {
                IERC721Upgradeable(auctionInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    auctionInfo.tokenId, 
                    ""
                );
            } else {
                IERC1155Upgradeable(auctionInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    auctionInfo.tokenId, 
                    auctionInfo.amountToSale, 
                    ""
                );
            }
            auctionInfo.status = Status.CANCELLED;
            emit AuctionWasCancelled(auctionId);
        }
    }

    /// @notice Determines the winners of auctions.
    /// @param winners_ Auction winner addresses.
    /// @param winningBids_ Winning bids.
    /// @param auctionIds_ Auction ids.
    /// @param signatures_ Signatures to verify the caller's permissions.
    function resolveAuctions(
        address[] calldata winners_, 
        uint256[] calldata winningBids_, 
        uint256[] calldata auctionIds_,
        bytes[] calldata signatures_
    ) 
        external 
        onlyProxy 
    {
        if (
            winners_.length != winningBids_.length ||
            winningBids_.length != auctionIds_.length ||
            auctionIds_.length != signatures_.length 
        ) {
            revert InvalidArrayLengths();
        }
        for (uint256 i = 0; i < winners_.length; i++) {
            if (notUniqueSignature[signatures_[i]]) {
                revert NotUniqueSignature(signatures_[i]);
            }
            bytes32 hash = keccak256(abi.encode(winners_[i], winningBids_[i], auctionIds_[i], AUCTION_HASH));
            if (hash.toEthSignedMessageHash().recover(signatures_[i]) != authorizer) {
                revert InvalidSignature(signatures_[i]);
            }
            AuctionInfo storage auctionInfo = auctions[auctionIds_[i]];
            if (auctionInfo.status != Status.ACTIVE) {
                revert InvalidStatus(auctionInfo.status);
            }
            auctionInfo.winner = winners_[i];
            auctionInfo.winningBid = winningBids_[i];
            notUniqueSignature[signatures_[i]] = true;
            emit AuctionWasResolved(winners_[i], winningBids_[i], auctionIds_[i]);
        }
    }

    /// @notice Processes auction payments.
    /// @param auctionIds_ Auction ids.
    /// @param isRedemption_ Array of boolean values defining whether the caller wants to redeem auction.
    function processPaymentsForAuctions(
        uint256[] calldata auctionIds_,
        bool[] calldata isRedemption_
    )   
        external 
        payable 
        nonReentrant
        onlyProxy 
    {
        if (auctionIds_.length != isRedemption_.length) {
            revert InvalidArrayLengths();
        }
        uint256 commissionPercentageMemory = commissionPercentage;
        CommissionRecipient[] memory commissionRecipientsMemory = commissionRecipients;
        uint256 msgValueSpent;
        for (uint256 i = 0; i < auctionIds_.length; i++) {
            AuctionInfo storage auctionInfo = auctions[auctionIds_[i]];
            if (auctionInfo.status != Status.ACTIVE) {
                revert InvalidStatus(auctionInfo.status);
            }
            uint256 paymentAmount;
            if (isRedemption_[i]) {
                if (auctionInfo.auctionType != AuctionType.EBAY) {
                    revert InvalidAuctionTypeForRedemption(auctionIds_[i]);
                }
                paymentAmount = auctionInfo.redemptionPrice;
            } else {
                if (msg.sender != auctionInfo.winner) {
                    revert InvalidCallee();
                }
                paymentAmount = auctionInfo.winningBid;
            }
            msgValueSpent += _processPayment(
                commissionRecipientsMemory, 
                auctionInfo.seller,
                auctionInfo.paymentCurrency,
                auctionInfo.token,
                auctionInfo.tokenId,
                commissionPercentageMemory,
                paymentAmount,
                auctionInfo.isRoyaltySupported
            );
            if (auctionInfo.isERC721) {
                IERC721Upgradeable(auctionInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    auctionInfo.tokenId, 
                    ""
                );
            } else {
                IERC1155Upgradeable(auctionInfo.token).safeTransferFrom(
                    address(this), 
                    msg.sender, 
                    auctionInfo.tokenId, 
                    auctionInfo.amountToSale, 
                    ""
                );
            }
            auctionInfo.status = Status.CLOSED;
            emit PaymentForAuctionWasProcessed(msg.sender, paymentAmount, auctionIds_[i]);
        }
        if (msg.value > msgValueSpent) {
            payable(msg.sender).sendValue(msg.value - msgValueSpent);
        }
    } 

    /// @notice Retrieves the current `_saleId` value.
    /// @return Current `_saleId` value.
    function currentSaleId() external view returns (uint256) {
        return _saleId.current();
    }

    /// @notice Retrieves the current `_auctionId` value.
    /// @return Current `_auctionId` value.
    function currentAuctionId() external view returns (uint256) {
        return _auctionId.current();
    }

    /// @notice Updates commission recipient addresses and percentages.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param commissionRecipientAddresses_ Commission recipient addresses.
    /// @param commissionRecipientPercentages_ Commission recipient percentages.
    function updateCommissionRecipients(
        address payable[] calldata commissionRecipientAddresses_, 
        uint256[] calldata commissionRecipientPercentages_
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (commissionRecipientAddresses_.length != commissionRecipientPercentages_.length) {
            revert InvalidArrayLengths();
        }
        uint256 percentagesSum;
        for (uint256 i = 0; i < commissionRecipientPercentages_.length; i++) {
            percentagesSum += commissionRecipientPercentages_[i];
        }
        if (percentagesSum != BASE_PERCENTAGE) {
            revert InvalidPercentagesSum();
        }
        CommissionRecipient[] memory m_commissionRecipients = commissionRecipients;
        delete commissionRecipients;
        for (uint256 i = 0; i < commissionRecipientAddresses_.length; i++) {
            if (commissionRecipientAddresses_[i] == address(0)) {
                revert ZeroAddressEntry();
            }
            commissionRecipients.push(CommissionRecipient(
                commissionRecipientAddresses_[i],
                commissionRecipientPercentages_[i]
            ));
        }
        emit CommissionRecipientsWereUpdated(m_commissionRecipients, commissionRecipients);
    }

    /// @notice Adds `currencies_` to the list of supported currencies. 
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param currencies_ Currency addresses.
    function addSupportedCurrencies(
        address[] calldata currencies_
    ) 
        public 
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < currencies_.length; i++) {
            isSupportedCurrency[currencies_[i]] = true;
        }
        emit SupportedCurrenciesWereAdded(currencies_);
    }

    /// @notice Returns true if this contract implements the interface defined by `interfaceId_`.
    /// @param interfaceId_ Interface id.
    /// @return Boolean value indicating whether this contract implements the interface defined by `interfaceId_`.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId_);
    }

    /// @notice Required by the UUPS module.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Processes the payment. Includes royalty split and sales commission.
    /// @param commissionRecipients_ Commission recipients.
    /// @param seller_ Seller address.
    /// @param paymentCurrency_ Payment currency address.
    /// @param token_ Token address.
    /// @param tokenId_ Token id.
    /// @param commissionPercentage_ Commission percentage.
    /// @param paymentAmount_ Payment amount.
    /// @param isRoyaltySupported_ Boolean value defining whether the token supports royalty.
    function _processPayment(
        CommissionRecipient[] memory commissionRecipients_,
        address payable seller_,
        address paymentCurrency_,
        address token_,
        uint256 tokenId_,
        uint256 commissionPercentage_,
        uint256 paymentAmount_,
        bool isRoyaltySupported_
    ) 
        private 
        returns (uint256 msgValueSpent_)
    {
        if (paymentCurrency_ != address(0)) {
            IERC20Upgradeable(paymentCurrency_).safeTransferFrom(msg.sender, address(this), paymentAmount_);
        }
        uint256 totalRoyaltyAmount;
        if (isRoyaltySupported_) {
            totalRoyaltyAmount = _processRoyalties(paymentCurrency_, token_, tokenId_, paymentAmount_);
        }
        unchecked {
            uint256 commissionAmount = paymentAmount_ * commissionPercentage_ / BASE_PERCENTAGE;
            if (paymentCurrency_ != address(0)) {
                IERC20Upgradeable(paymentCurrency_).safeTransfer(seller_, paymentAmount_ - totalRoyaltyAmount - commissionAmount);
                for (uint256 i = 0; i < commissionRecipients_.length; i++) {
                    IERC20Upgradeable(paymentCurrency_).safeTransfer(
                        commissionRecipients_[i].commissionRecipientAddress, 
                        commissionAmount * commissionRecipients_[i].commissionRecipientPercentage / BASE_PERCENTAGE
                    );
                }
            } else {
                msgValueSpent_ += paymentAmount_;
                seller_.sendValue(paymentAmount_ - totalRoyaltyAmount - commissionAmount);
                for (uint256 i = 0; i < commissionRecipients_.length; i++) {
                    commissionRecipients_[i].commissionRecipientAddress.sendValue(
                        commissionAmount * commissionRecipients_[i].commissionRecipientPercentage / BASE_PERCENTAGE
                    );
                }
            }
        }
    }

    /// @notice Processes royalties.
    /// @param paymentCurrency_ Payment currency address.
    /// @param token_ Token address (ERC721 or ERC1155).
    /// @param tokenId_ Token id.
    /// @param paymentAmount_ Payment amount.
    /// @return totalRoyaltyAmount_ Summed up royalty amount.
    function _processRoyalties(
        address paymentCurrency_,
        address token_,
        uint256 tokenId_,
        uint256 paymentAmount_
    ) 
        private
        returns (uint256 totalRoyaltyAmount_)
    {
        address payable[] memory recipients;
        uint256[] memory shares;
        if (IERC165Upgradeable(token_).supportsInterface(ROYALTY_SPLITTER_INTERFACE_ID)) {
            uint256[] memory percentages;
            (recipients, percentages) = IRoyaltySplitter(token_).getRoyalties(tokenId_);
            shares = new uint256[](recipients.length);
            unchecked {
                for (uint256 i = 0; i < recipients.length; i++) {
                    uint256 share = paymentAmount_ * percentages[i] / BASE_PERCENTAGE;
                    shares[i] = share;
                    totalRoyaltyAmount_ += share;
                }
            }
        } else {
            (address recipient, uint256 share) = IERC2981Upgradeable(token_).royaltyInfo(tokenId_, paymentAmount_);
            recipients = new address payable[](1);
            shares = new uint256[](1);
            recipients[0] = payable(recipient);
            shares[0] = share;
            totalRoyaltyAmount_ = share;
        }
        if (paymentCurrency_ != address(0)) {
            for (uint256 i = 0; i < recipients.length; i++) {
                IERC20Upgradeable(paymentCurrency_).safeTransfer(recipients[i], shares[i]);
            }
        } else {
            for (uint256 i = 0; i < recipients.length; i++) {
                recipients[i].sendValue(shares[i]);
            }
        }
    }
}