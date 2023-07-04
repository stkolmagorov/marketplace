const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("MarketplaceV1", () => {
    const ONE_ETHER = ethers.utils.parseEther("1");
    const SIGNATURE_EXAMPLE 
        = "0x21fbf0696d5e0aa2ef41a2b4ffb623bcaf070461d61cf7251c74161f82fec3a4370854bc0a34b3ab487c1bc021cd318c734c51ae29374f2beb0e6f2dd49b4bf41c";

    const generateSignatureForAuction = async (winner, winningBid, auctionId) => {
        const AUCTION_HASH = await marketplace.AUCTION_HASH();
        const hash = ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
                ["address", "uint256", "uint256", "bytes32"],
                [winner.address, winningBid, auctionId, AUCTION_HASH]
            )
        );
        return authorizer.signMessage(ethers.utils.arrayify(hash));
    }

    const generateSignatureForSale = async (approvedBuyers, approvedPricesPerToken, saleId) => {
        const SALE_HASH = await marketplace.SALE_HASH();
        const hash = ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
                ["address[]", "uint256[]", "uint256", "bytes32"],
                [approvedBuyers, approvedPricesPerToken, saleId, SALE_HASH]
            )
        );
        return authorizer.signMessage(ethers.utils.arrayify(hash));
    }

    before(async () => {
        [   
            owner,
            alice, 
            firstCommissionRecipient, 
            secondCommissionRecipient,
            firstRoyaltyRecipient,
            secondRoyaltyRecipient,
            authorizer
        ] = await ethers.getSigners();
    });

    const fixture = async () => {
        const ERC721MockSimple = await ethers.getContractFactory("ERC721MockSimple");
        const erc721MockSimpleInstance = await ERC721MockSimple.deploy(); 
        const ERC721Mock = await ethers.getContractFactory("ERC721Mock");
        const erc721MockInstance = await ERC721Mock.deploy(firstRoyaltyRecipient.address); 
        const ERC1155Mock = await ethers.getContractFactory("ERC1155Mock");
        const erc1155MockInstance = await ERC1155Mock.deploy(
            [firstRoyaltyRecipient.address, secondRoyaltyRecipient.address],
            [2500, 2500]
        ); 
        const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
        const erc20MockInstance = await ERC20Mock.deploy();
        const Marketplace = await ethers.getContractFactory("MarketplaceV1");
        const marketplaceInstance = await upgrades.deployProxy(
            Marketplace, 
            [
                [firstCommissionRecipient.address, secondCommissionRecipient.address],
                [erc20MockInstance.address],
                [3000, 7000],
                authorizer.address,
                500
            ],
            { initializer: "initialize" }
        );
        await erc721MockSimpleInstance.setApprovalForAll(marketplaceInstance.address, true);
        await erc721MockInstance.setApprovalForAll(marketplaceInstance.address, true);
        await erc1155MockInstance.setApprovalForAll(marketplaceInstance.address, true);
        return { erc721MockSimpleInstance, erc721MockInstance, erc1155MockInstance, erc20MockInstance, marketplaceInstance };
    }

    beforeEach(async () => {
        const { 
            erc721MockSimpleInstance, 
            erc721MockInstance, 
            erc1155MockInstance, 
            erc20MockInstance, 
            marketplaceInstance 
        } = await loadFixture(fixture);
        erc721MockSimple = erc721MockSimpleInstance;
        erc721Mock = erc721MockInstance;
        erc1155Mock = erc1155MockInstance;
        erc20Mock = erc20MockInstance;
        marketplace = marketplaceInstance;
    });

    it("Successful initialize() execution", async () => {
        // Checks
        expect(await marketplace.hasRole(await marketplace.DEFAULT_ADMIN_ROLE(), owner.address)).to.equal(true);
        let commissionRecipient = await marketplace.commissionRecipients(0);
        expect(commissionRecipient.commissionRecipientAddress).to.equal(firstCommissionRecipient.address);
        expect(commissionRecipient.commissionRecipientPercentage).to.equal(3000);
        commissionRecipient = await marketplace.commissionRecipients(1);
        expect(commissionRecipient.commissionRecipientAddress).to.equal(secondCommissionRecipient.address);
        expect(commissionRecipient.commissionRecipientPercentage).to.equal(7000);
        expect(await marketplace.isSupportedCurrency(ethers.constants.AddressZero)).to.equal(true);
        expect(await marketplace.isSupportedCurrency(erc20Mock.address)).to.equal(true);
        expect(await marketplace.commissionPercentage()).to.equal(500);
        expect(await marketplace.currentSaleId()).to.equal(0);
        expect(await marketplace.supportsInterface(0x4e2312e0)).to.equal(true);
        expect(await marketplace.supportsInterface(0x7965db0b)).to.equal(true);
        // Attempt to initialize again
        await expect(marketplace.initialize(
            [firstCommissionRecipient.address, secondCommissionRecipient.address],
            [erc20Mock.address],
            [3000, 7000],
            authorizer.address,
            500
        )).to.be.revertedWith("Initializable: contract is already initialized");
    });

    it("Successful updateCommissionPercentage() execution", async () => {
        // Attempt to update from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).updateCommissionPercentage(100))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        // Attempt to update with exceeded limit percentage
        await expect(marketplace.updateCommissionPercentage(2000))
            .to.be.revertedWith("MaximumCommissionPercentageWasExceeded");
        // Successful updating
        await marketplace.updateCommissionPercentage(1000);
        expect(await marketplace.commissionPercentage()).to.equal(1000);
    });

    it("Successful addSupportedCurrencies() execution", async () => {
        // Attempt to add from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).addSupportedCurrencies([alice.address]))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        // Successful addition
        await marketplace.addSupportedCurrencies([alice.address]);
        expect(await marketplace.isSupportedCurrency(alice.address)).to.equal(true);
    });

    it("Successful removeSupportedCurrencies() execution", async () => {
        // Attempt to remove from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).removeSupportedCurrencies([erc20Mock.address]))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        // Attempt to remove native currency
        await expect(marketplace.removeSupportedCurrencies([ethers.constants.AddressZero]))
            .to.be.revertedWith("ZeroAddressEntry");
        // Successful removal
        await marketplace.removeSupportedCurrencies([erc20Mock.address]);
        expect(await marketplace.isSupportedCurrency(erc20Mock.address)).to.equal(false);
    });

    it("Successful updateAuthorizer() execution", async () => {
        // Attempt to remove from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).updateAuthorizer(authorizer.address))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        // Attempt to update with the same address
        await expect(marketplace.updateAuthorizer(authorizer.address)).to.be.revertedWith("InvalidAuthorizer");
        // Attempt to update with zero address
        await expect(marketplace.updateAuthorizer(ethers.constants.AddressZero)).to.be.revertedWith("InvalidAuthorizer");
        // Successful updating
        await marketplace.updateAuthorizer(owner.address);
        expect(await marketplace.authorizer()).to.equal(owner.address);
    });

    it("Successful updateCommissionRecipients() execution", async () => {
        // Attempt to update from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).updateCommissionRecipients([erc20Mock.address], [10000]))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        // Attempt to update with invalid array lengths
        await expect(marketplace.updateCommissionRecipients([ethers.constants.AddressZero], [1, 1]))
            .to.be.revertedWith("InvalidArrayLengths");
        // Attempt to update with invalid percentages sum
        await expect(marketplace.updateCommissionRecipients([ethers.constants.AddressZero], [1]))
            .to.be.revertedWith("InvalidPercentagesSum");
        // Attempt to update with zero address
        await expect(marketplace.updateCommissionRecipients([ethers.constants.AddressZero], [10000]))
            .to.be.revertedWith("ZeroAddressEntry");
        // Successful updating
        await marketplace.updateCommissionRecipients([alice.address], [10000]);
        expect((await marketplace.commissionRecipients(0)).commissionRecipientAddress).to.equal(alice.address);
        expect((await marketplace.commissionRecipients(0)).commissionRecipientPercentage).to.equal(10000);
    });

    it("Successful createSales() execution", async () => {
        // Attempt to create sales with invalid array length
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create sales with invalid array length
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create sales with invalid array length
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create sales with invalid array length
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create sales with invalid array length
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create sales with invalid amount of tokens to sale
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [100, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("InvalidAmountOfTokensToSale");
        // Attempt to create sales with invalid amount of tokens to sale
        await expect(marketplace.createSales(
            [ethers.constants.AddressZero],
            [erc1155Mock.address],
            [0],
            [0],
            [ONE_ETHER],
            [false]
        )).to.be.revertedWith("InvalidAmountOfTokensToSale");
         // Attempt to create sales with unsupported currency
         await expect(marketplace.createSales(
            [alice.address],
            [erc721Mock.address],
            [0],
            [1],
            [ONE_ETHER],
            [true]
        )).to.be.revertedWith("UnsupportedCurrencyEntry");
        // Successful sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        );
        let saleInfo = await marketplace.sales(0);
        expect(saleInfo.seller).to.equal(owner.address);
        expect(saleInfo.paymentCurrency).to.equal(ethers.constants.AddressZero);
        expect(saleInfo.token).to.equal(erc721Mock.address);
        expect(saleInfo.tokenId).to.equal(0);
        expect(saleInfo.availableAmountToPurchase).to.equal(1);
        expect(saleInfo.purchasedAmount).to.equal(0);
        expect(saleInfo.pricePerToken).to.equal(ONE_ETHER);
        expect(saleInfo.isERC721).to.equal(true);
        expect(saleInfo.isRoyaltySupported).to.equal(true);
        expect(saleInfo.status).to.equal(1);
        saleInfo = await marketplace.sales(1);
        expect(saleInfo.seller).to.equal(owner.address);
        expect(saleInfo.paymentCurrency).to.equal(ethers.constants.AddressZero);
        expect(saleInfo.token).to.equal(erc1155Mock.address);
        expect(saleInfo.tokenId).to.equal(0);
        expect(saleInfo.availableAmountToPurchase).to.equal(100);
        expect(saleInfo.purchasedAmount).to.equal(0);
        expect(saleInfo.pricePerToken).to.equal(ONE_ETHER);
        expect(saleInfo.isERC721).to.equal(false);
        expect(saleInfo.isRoyaltySupported).to.equal(true);
        expect(saleInfo.status).to.equal(1);
        expect(await marketplace.currentSaleId()).to.equal(2);
    });

    it("Successful cancelSales() execution", async () => {
        // Sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        );
        // Attempt to cancel from non-seller account
        await expect(marketplace.connect(alice).cancelSales([0])).to.be.revertedWith("InvalidCallee");
        // Successful canceling
        const erc721MockBalance = await erc721Mock.balanceOf(owner.address);
        const erc1155MockBalance = await erc1155Mock.balanceOf(owner.address, 0);
        await marketplace.cancelSales([0, 1]);
        let sale = await marketplace.sales(0);
        expect(await erc721Mock.balanceOf(owner.address)).to.equal(erc721MockBalance.add(1));
        expect(await sale.status).to.equal(2);
        sale = await marketplace.sales(1);
        expect(await erc1155Mock.balanceOf(owner.address, 0)).to.equal(erc1155MockBalance.add(100));
        expect(await sale.status).to.equal(2);
        // Attempt to cancel again
        await expect(marketplace.cancelSales([0, 1])).to.be.revertedWith("InvalidStatus");
    });

    it("Successful resolveSale() execution", async () => {
        // Sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero],
            [erc721Mock.address],
            [0],
            [1],
            [ONE_ETHER],
            [true]
        );
        // Attempt to resolve with invalid array lengths
        await expect(marketplace.resolveSale(
            [alice.address, owner.address],
            [ONE_ETHER.div(2)],
            await generateSignatureForSale([alice.address, owner.address], [ONE_ETHER.div(2)], 0),
            0
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to resolve with invalid signature
        await expect(marketplace.resolveSale(
            [alice.address],
            [ONE_ETHER.div(2)],
            SIGNATURE_EXAMPLE,
            0
        )).to.be.revertedWith("InvalidSignature");
        // Attempt to resolve with invalid callee
        await expect(marketplace.connect(alice).resolveSale(
            [alice.address],
            [ONE_ETHER.div(2)],
            await generateSignatureForSale([alice.address], [ONE_ETHER.div(2)], 0),
            0
        )).to.be.revertedWith("InvalidCallee");
        // Attempt to resolve with zero price per token
        await expect(marketplace.resolveSale(
            [alice.address],
            [0],
            await generateSignatureForSale([alice.address], [0], 0),
            0
        )).to.be.revertedWith("InvalidApprovedPricePerToken");
        // Purchase
        await marketplace.processPaymentsForSales([0], [1], { value: ONE_ETHER });
        // Attempt to resolve with invalid sale status
        await expect(marketplace.resolveSale(
            [alice.address],
            [ONE_ETHER.div(2)],
            await generateSignatureForSale([alice.address], [ONE_ETHER.div(2)], 0),
            0
        )).to.be.revertedWith("InvalidStatus");
        // Sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero],
            [erc721Mock.address],
            [1],
            [1],
            [ONE_ETHER],
            [true]
        );
        // Successful resolving
        await marketplace.resolveSale(
            [alice.address],
            [ONE_ETHER.div(2)],
            await generateSignatureForSale([alice.address], [ONE_ETHER.div(2)], 1),
            1
        );
        // Successful purchasing
        await marketplace.connect(alice).processPaymentsForSales([1], [1], { value: ONE_ETHER.div(2) });
        expect(await erc721Mock.balanceOf(alice.address)).to.equal(1);
        // Attempt to resolve with the same signature
        await expect(marketplace.resolveSale(
            [firstCommissionRecipient.address],
            [ONE_ETHER.div(4)],
            await generateSignatureForSale([alice.address], [ONE_ETHER.div(2)], 1),
            1
        )).to.be.revertedWith("NotUniqueSignature");
    });

    it("Successful processPaymentsForSales() execution", async () => {
        // Sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero, erc20Mock.address],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        );
        // Attempt to process payments with invalid array lengths
        await expect(marketplace.processPaymentsForSales([2], [100, 500])).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to process payments nonexistent sale
        await expect(marketplace.processPaymentsForSales([2], [100])).to.be.revertedWith("InvalidStatus");
        // Attempts to process payments with invalid amount of tokens
        await expect(marketplace.processPaymentsForSales([0], [100])).to.be.revertedWith("InvalidAmountOfTokensToPurchase");
        await expect(marketplace.processPaymentsForSales([1], [0])).to.be.revertedWith("InvalidAmountOfTokensToPurchase");
        await erc20Mock.approve(marketplace.address, ONE_ETHER.mul(101));
        await erc1155Mock.safeTransferFrom(owner.address, marketplace.address, 0, 200, ethers.constants.HashZero);
        await expect(marketplace.processPaymentsForSales([1], [101])).to.be.revertedWith("panic code 0x11");
        // Successful process payments with msg.value
        let ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
        await marketplace.connect(alice).processPaymentsForSales([0], [1], { value: ONE_ETHER });
        expect(await ethers.provider.getBalance(owner.address)).to.equal(ownerBalanceBefore.add(ONE_ETHER.mul(85).div(100)));
        expect(await erc721Mock.balanceOf(alice.address)).to.equal(1);
        let sale = await marketplace.sales(0);
        expect(sale.availableAmountToPurchase).to.equal(0);
        expect(sale.purchasedAmount).to.equal(1);
        expect(sale.status).to.equal(3);
        // Successful process payments with ERC20 tokens and msg.value
        const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);
        await erc20Mock.transfer(alice.address, ONE_ETHER);
        await erc20Mock.connect(alice).approve(marketplace.address, ONE_ETHER);
        ownerBalanceBefore = await erc20Mock.balanceOf(owner.address);
        await marketplace.connect(alice).processPaymentsForSales([1], [1], { value: ONE_ETHER })
        const precision = ethers.utils.parseEther("0.001");
        expect(await ethers.provider.getBalance(alice.address)).to.be.closeTo(aliceBalanceBefore, precision);
        expect(await erc1155Mock.balanceOf(alice.address, 0)).to.equal(1);
        expect(await erc20Mock.balanceOf(owner.address)).to.equal(ownerBalanceBefore.add(ONE_ETHER.mul(45).div(100)));
        // Sales creation
        await marketplace.createSales(
            [ethers.constants.AddressZero, erc20Mock.address],
            [erc721MockSimple.address, erc721MockSimple.address],
            [0, 1],
            [1, 1],
            [ONE_ETHER, ONE_ETHER],
            [true, true]
        );
        // Successful process payments ERC721 without royalties with msg.value and ERC20 tokens
        await erc20Mock.transfer(alice.address, ONE_ETHER);
        await erc20Mock.connect(alice).approve(marketplace.address, ONE_ETHER);
        await marketplace.connect(alice).processPaymentsForSales([2, 3], [1, 1], { value: ONE_ETHER });
        // Sales creation
        await marketplace.createSales(
            [erc20Mock.address],
            [erc1155Mock.address],
            [1],
            [1000],
            [ONE_ETHER],
            [false]
        );
        // Resolve sale
        await marketplace.resolveSale(
            [alice.address],
            [ONE_ETHER.div(2)],
            await generateSignatureForSale([alice.address], [ONE_ETHER.div(2)], 4),
            4
        );
        expect(await marketplace.approvedPricePerTokenBySaleIdAndApprovedBuyer(4, alice.address)).to.equal(ONE_ETHER.div(2));
        // Successful process payments for resolved sale
        await erc20Mock.transfer(alice.address, ONE_ETHER.mul(50));
        await erc20Mock.connect(alice).approve(marketplace.address, ONE_ETHER.mul(50));
        await marketplace.connect(alice).processPaymentsForSales([4], [100]);
        sale = await marketplace.sales(4);
        expect(sale.availableAmountToPurchase).to.equal(900);
        expect(await erc20Mock.balanceOf(alice.address)).to.equal(0);
    });

    it("Successful createAuctions() execution", async () => {
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER],
            [true, true],
            [1, 1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true],
            [1, 1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid array length
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, true],
            [1]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to create auctions with invalid amount of tokens to sale
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [100, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [0, 0]
        )).to.be.revertedWith("InvalidAmountOfTokensToSale");
        // Attempt to create auctions with invalid amount of tokens to sale
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero],
            [erc1155Mock.address],
            [0],
            [0],
            [ONE_ETHER],
            [false],
            [0]
        )).to.be.revertedWith("InvalidAmountOfTokensToSale");
        // Attempt to create auctions with unsupported currency
        await expect(marketplace.createAuctions(
            [alice.address],
            [erc721Mock.address],
            [0],
            [1],
            [ONE_ETHER],
            [true],
            [0]
        )).to.be.revertedWith("UnsupportedCurrencyEntry");
        // Attempt to create auctions with invalid redemption price
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero],
            [erc721Mock.address],
            [0],
            [1],
            [ONE_ETHER],
            [true],
            [0]
        )).to.be.revertedWith("InvalidRedemptionPrice");
        // Attempt to create auctions with invalid redemption price
        await expect(marketplace.createAuctions(
            [ethers.constants.AddressZero],
            [erc721Mock.address],
            [0],
            [1],
            [0],
            [true],
            [1]
        )).to.be.revertedWith("InvalidRedemptionPrice");
        // Successful auctions creation
        await marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        );
        let auctionInfo = await marketplace.auctions(0);
        expect(auctionInfo.seller).to.equal(owner.address);
        expect(auctionInfo.winner).to.equal(ethers.constants.AddressZero);
        expect(auctionInfo.paymentCurrency).to.equal(ethers.constants.AddressZero);
        expect(auctionInfo.token).to.equal(erc721Mock.address);
        expect(auctionInfo.tokenId).to.equal(0);
        expect(auctionInfo.winningBid).to.equal(0);
        expect(auctionInfo.amountToSale).to.equal(1);
        expect(auctionInfo.redemptionPrice).to.equal(ONE_ETHER);
        expect(auctionInfo.isERC721).to.equal(true);
        expect(auctionInfo.isRoyaltySupported).to.equal(true);
        expect(auctionInfo.status).to.equal(1);
        expect(auctionInfo.auctionType).to.equal(1);
        auctionInfo = await marketplace.auctions(1);
        expect(auctionInfo.seller).to.equal(owner.address);
        expect(auctionInfo.winner).to.equal(ethers.constants.AddressZero);
        expect(auctionInfo.paymentCurrency).to.equal(ethers.constants.AddressZero);
        expect(auctionInfo.token).to.equal(erc1155Mock.address);
        expect(auctionInfo.tokenId).to.equal(0);
        expect(auctionInfo.winningBid).to.equal(0);
        expect(auctionInfo.amountToSale).to.equal(100);
        expect(auctionInfo.redemptionPrice).to.equal(ONE_ETHER);
        expect(auctionInfo.isERC721).to.equal(false);
        expect(auctionInfo.isRoyaltySupported).to.equal(true);
        expect(auctionInfo.status).to.equal(1);
        expect(auctionInfo.auctionType).to.equal(1);
        expect(await marketplace.currentAuctionId()).to.equal(2);
    });

    it("Successful cancelAuctions() execution", async () => {
        // Auctions creation
        await marketplace.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        );
        // Attempt to cancel from non-seller account
        await expect(marketplace.connect(alice).cancelAuctions([0])).to.be.revertedWith("InvalidCallee");
        // Successful canceling
        const erc721MockBalance = await erc721Mock.balanceOf(owner.address);
        const erc1155MockBalance = await erc1155Mock.balanceOf(owner.address, 0);
        await marketplace.cancelAuctions([0, 1]);
        let auction = await marketplace.auctions(0);
        expect(await erc721Mock.balanceOf(owner.address)).to.equal(erc721MockBalance.add(1));
        expect(await auction.status).to.equal(2);
        auction = await marketplace.auctions(1);
        expect(await erc1155Mock.balanceOf(owner.address, 0)).to.equal(erc1155MockBalance.add(100));
        expect(await auction.status).to.equal(2);
        // Attempt to cancel again
        await expect(marketplace.cancelAuctions([0, 1])).to.be.revertedWith("InvalidStatus");
    });

    it("Successful resolveAuctions() execution", async () => {
        // Attempt to resolve auctions with invalid array lengths
        await expect(marketplace.resolveAuctions(
            [owner.address],
            [ONE_ETHER, ONE_ETHER],
            [0, 1],
            ["0x", "0x"]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to resolve auctions with invalid array lengths
        await expect(marketplace.resolveAuctions(
            [owner.address, alice.address],
            [ONE_ETHER, ONE_ETHER],
            [0],
            ["0x", "0x"]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to resolve auctions with invalid array lengths
        await expect(marketplace.resolveAuctions(
            [owner.address, alice.address],
            [ONE_ETHER, ONE_ETHER],
            [0, 1],
            ["0x"]
        )).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to resolve auction with invalid signature
        await expect(marketplace.resolveAuctions(
            [owner.address],
            [ONE_ETHER],
            [0],
            [SIGNATURE_EXAMPLE]
        )).to.be.revertedWith("InvalidSignature");
        // Auction creation
        await marketplace.createAuctions(
            [ethers.constants.AddressZero],
            [erc721Mock.address],
            [0],
            [1],
            [ONE_ETHER],
            [true],
            [1]
        );
        // Successful resolving
        await marketplace.resolveAuctions(
            [alice.address],
            [ONE_ETHER],
            [0],
            [await generateSignatureForAuction(alice, ONE_ETHER, 0)]
        );
        // Attempt to resolve auction with the same signature
        await expect(marketplace.resolveAuctions(
            [owner.address],
            [ONE_ETHER],
            [0],
            [await generateSignatureForAuction(alice, ONE_ETHER, 0)]
        )).to.be.revertedWith("NotUniqueSignature");
        // Attempt to resolve non-existent auction
        await expect(marketplace.resolveAuctions(
            [owner.address],
            [ONE_ETHER],
            [1],
            [await generateSignatureForAuction(owner, ONE_ETHER, 1)]
        )).to.be.revertedWith("InvalidStatus");
    });

    it("Successful processPaymentsForAuctions() execution", async () => {
        // Auctions creation
        await marketplace.createAuctions(
            [ethers.constants.AddressZero, erc20Mock.address],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [0, ONE_ETHER],
            [true, false],
            [0, 1]
        );
        // Attempt to process payments with invalid array lengths
        await expect(marketplace.processPaymentsForAuctions([0], [false, true])).to.be.revertedWith("InvalidArrayLengths");
        // Attempt to process payments with invalid status
        await expect(marketplace.processPaymentsForAuctions([2], [true])).to.be.revertedWith("InvalidStatus");
        // Attempt to process payments with invalid auction type for redemption
        await expect(marketplace.processPaymentsForAuctions([0], [true])).to.be.revertedWith("InvalidAuctionTypeForRedemption");
        // Attempt to process payments with invalid auction with invalid callee (not winner)
        await expect(marketplace.processPaymentsForAuctions([0], [false])).to.be.revertedWith("InvalidCallee");
        // Successful process payments with msg.value
        let ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
        await marketplace.connect(alice).resolveAuctions(
            [alice.address], 
            [ONE_ETHER], 
            [0], 
            [await generateSignatureForAuction(alice, ONE_ETHER, 0)]
        );
        await marketplace.connect(alice).processPaymentsForAuctions([0], [false], { value: ONE_ETHER });
        expect(await ethers.provider.getBalance(owner.address)).to.equal(ownerBalanceBefore.add(ONE_ETHER.mul(85).div(100)));
        expect(await erc721Mock.balanceOf(alice.address)).to.equal(1);
        let auction = await marketplace.auctions(0);
        expect(auction.status).to.equal(3);
        // Successful process payments with msg.value and ERC20
        const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);
        await erc20Mock.transfer(alice.address, ONE_ETHER);
        await erc20Mock.connect(alice).approve(marketplace.address, ONE_ETHER);
        ownerBalanceBefore = await erc20Mock.balanceOf(owner.address);
        await marketplace.connect(alice).processPaymentsForAuctions([1], [true], { value: ONE_ETHER })
        const precision = ethers.utils.parseEther("0.001");
        expect(await ethers.provider.getBalance(alice.address)).to.be.closeTo(aliceBalanceBefore, precision);
        expect(await erc1155Mock.balanceOf(alice.address, 0)).to.equal(100);
        expect(await erc20Mock.balanceOf(owner.address)).to.equal(ownerBalanceBefore.add(ONE_ETHER.mul(45).div(100)));
        auction = await marketplace.auctions(1);
        expect(auction.status).to.equal(3);
        // Auction creation without royalties
        await marketplace.createAuctions(
            [ethers.constants.AddressZero, erc20Mock.address],
            [erc721MockSimple.address, erc721MockSimple.address],
            [0, 1],
            [1, 1],
            [ONE_ETHER, ONE_ETHER],
            [true, true],
            [1, 1]
        );
        // Batch buying
        await erc20Mock.transfer(alice.address, ONE_ETHER);
        await erc20Mock.connect(alice).approve(marketplace.address, ONE_ETHER);
        const ownerBalanceBeforeInNativeCurrency = await ethers.provider.getBalance(owner.address);
        const ownerBalanceBeforeInERC20Currency = await erc20Mock.balanceOf(owner.address);
        await marketplace.connect(alice).processPaymentsForAuctions([2, 3], [true, true], { value: ONE_ETHER });
        expect(await erc721MockSimple.balanceOf(alice.address)).to.equal(2);
        auction = await marketplace.auctions(2);
        expect(auction.status).to.equal(3);
        auction = await marketplace.auctions(3);
        expect(auction.status).to.equal(3);
        expect(await ethers.provider.getBalance(owner.address)).to.equal(ownerBalanceBeforeInNativeCurrency.add(ONE_ETHER.mul(95).div(100)));
        expect(await erc20Mock.balanceOf(owner.address)).to.equal(ownerBalanceBeforeInERC20Currency.add(ONE_ETHER.mul(95).div(100)));
    });

    it("Successful _authorizeUpgrade() execution and onlyProxy checks", async () => {
        // Attempt to upgrade from non-granted to DEFAULT_ADMIN_ROLE
        await expect(marketplace.connect(alice).upgradeTo(erc20Mock.address))
            .to.be.revertedWith(
                `AccessControl: account ${(alice.address).toLowerCase()} is missing role ${await marketplace.DEFAULT_ADMIN_ROLE()}`
            );
        const implementation = await ethers.getContractAt(
            "MarketplaceV1", 
            await upgrades.erc1967.getImplementationAddress(marketplace.address)
        );
        // Successful upgrading
        await expect(marketplace.upgradeTo(implementation.address)).to.emit(marketplace, "Upgraded");
        // Check onlyProxy modifiers
        await expect(implementation.createSales(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false]
        )).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.cancelSales([0])).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.resolveSale(
            [owner.address],
            [ONE_ETHER],
            await generateSignatureForSale([owner.address], [ONE_ETHER], 0),
            0
        )).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.processPaymentsForSales([0], [0])).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.createAuctions(
            [ethers.constants.AddressZero, ethers.constants.AddressZero],
            [erc721Mock.address, erc1155Mock.address],
            [0, 0],
            [1, 100],
            [ONE_ETHER, ONE_ETHER],
            [true, false],
            [1, 1]
        )).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.cancelAuctions([0])).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.resolveAuctions(
            [owner.address],
            [ONE_ETHER],
            [1],
            [await generateSignatureForAuction(owner, ONE_ETHER, 1)]
        )).to.be.revertedWith("Function must be called through delegatecall");
        await expect(implementation.processPaymentsForAuctions([0], [true])).to.be.revertedWith("Function must be called through delegatecall");
    });
});