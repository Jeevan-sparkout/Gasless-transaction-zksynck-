import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

async function main() {
  console.log("Deploying MyERC20Token on ZKsync Era Sepolia...");

  // Initialize the wallet
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY || "");

  // Create a deployer object
  const deployer = new Deployer(hre, wallet);

  // Load the artifact of the contract you want to deploy
  const artifact = await deployer.loadArtifact("MyERC20Token");

  // Deploy the contract
  // No constructor arguments for MyERC20Token in our case
  const tokenContract = await deployer.deploy(artifact, []);

  // Show the contract address
  const contractAddress = await tokenContract.getAddress();
  console.log(`MyERC20Token was deployed to ${contractAddress}`);

  // Verify the contract on explorer
  // Note: Verification might fail if done immediately after deployment
  console.log("Verifying contract on explorer...");
  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      contract: "contracts/MyERC20Token.sol:MyERC20Token",
      constructorArguments: [],
    });
    console.log("Verification successful!");
  } catch (error) {
    console.error("Verification failed:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
