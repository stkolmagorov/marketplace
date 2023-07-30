const { ethers, upgrades } = require("hardhat");

async function main() {
    const commissionRecipientAddresses = undefined;
    const commissionRecipientPercentages = undefined;
    const supportedCurrencyAddresses = undefined;
    const authorizer = undefined;
    const commissionPercentage = undefined;
    const Marketplace = await ethers.getContractFactory("MarketplaceV1");
    const marketplace = await upgrades.deployProxy(
        Marketplace, 
        [
            commissionRecipientAddresses,
            commissionRecipientPercentages,
            supportedCurrencyAddresses,
            authorizer,
            commissionPercentage
        ],
        { initializer: "initialize", kind: "uups" }
    );
    console.log("Address: ", marketplace.address);
}
  
main().catch((error) => {
    console.error(error);
    process.exit(1);
});