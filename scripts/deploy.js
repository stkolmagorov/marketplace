const { ethers, upgrades } = require("hardhat");

async function main() {
    const commissionRecipientAddresses = [];
    const commissionRecipientPercentages = [];
    const supportedCurrencyAddresses = [];
    const signer = undefined;
    const commissionPercentage = undefined;
    const Marketplace = await ethers.getContractFactory("MarketplaceV1");
    const marketplace = await upgrades.deployProxy(
        Marketplace, 
        [
            commissionRecipientAddresses,
            supportedCurrencyAddresses,
            commissionRecipientPercentages,
            signer,
            commissionPercentage
        ],
        { initializer: "initialize"}
    );
    console.log("Address: ", marketplace.address);
}
  
main().catch((error) => {
    console.error(error);
    process.exit(1);
});