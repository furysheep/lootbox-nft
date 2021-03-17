// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  // We get the contract to deploy
  /*
  const RNGenerator = await hre.ethers.getContractFactory(
    "RandomNumberConsumer"
  );
  const generator = await RNGenerator.deploy();
  await generator.deployed();

  const LootBox = await hre.ethers.getContractFactory("LootBox");
  const lootbox = await LootBox.deploy(
    "0x2d730E7D5c85134a38D835042688a8fa3fF87623",
    1,
    generator.address
  );

  await lootbox.deployed(generator.address);

  await generator.setLootboxContract(lootbox.address);

  console.log("RN Generator deployed to:", generator.address);
  console.log("LootBox deployed to:", lootbox.address);
  */

  const NFTAuctionSale = await hre.ethers.getContractFactory("NFTAuctionSale");
  const auctionSale = await NFTAuctionSale.deploy();
  console.log("Auction sale deployed to:", auctionSale.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
