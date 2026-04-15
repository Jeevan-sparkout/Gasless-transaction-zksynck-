import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

async function main() {
  const privateKey = process.env.WALLET_PRIVATE_KEY || "";
  if (!privateKey) {
    throw new Error("WALLET_PRIVATE_KEY is missing");
  }

  const wallet = new Wallet(privateKey);
  const owner = await wallet.getAddress();
  const deployer = new Deployer(hre, wallet);
  const existingPaymaster = process.env.PAYMASTER_ADDRESS;

  console.log(`Deployer: ${owner}`);
  const maxGasLimitPerTx = 2_000_000;
  let paymasterAddress: string;

  if (existingPaymaster && existingPaymaster.length > 0) {
    paymasterAddress = existingPaymaster;
    console.log(`Using existing GaslessSponsoredPaymaster: ${paymasterAddress}`);
  } else {
    console.log("Deploying GaslessSponsoredPaymaster...");
    const gaslessArtifact = await deployer.loadArtifact(
      "contracts/paymasters/GaslessSponsoredPaymaster.sol:GaslessSponsoredPaymaster"
    );
    const paymaster = await deployer.deploy(gaslessArtifact, [owner, maxGasLimitPerTx]);
    paymasterAddress = await paymaster.getAddress();
    console.log(`GaslessSponsoredPaymaster deployed at: ${paymasterAddress}`);
  }

  console.log("Deploying MyERC20Token...");
  const tokenArtifact = await deployer.loadArtifact(
    "contracts/MyERC20Token.sol:MyERC20Token"
  );
  const token = await deployer.deploy(tokenArtifact, [paymasterAddress]);
  const tokenAddress = await token.getAddress();
  console.log(`MyERC20Token deployed at: ${tokenAddress}`);

  console.log("Attempting verification...");
  try {
    await hre.run("verify:verify", {
      address: paymasterAddress,
      contract: "contracts/paymasters/GaslessSponsoredPaymaster.sol:GaslessSponsoredPaymaster",
      constructorArguments: [owner, maxGasLimitPerTx],
    });
    console.log("Paymaster verified.");
  } catch (error) {
    console.error("Paymaster verification failed:", error);
  }

  try {
    await hre.run("verify:verify", {
      address: tokenAddress,
      contract: "contracts/MyERC20Token.sol:MyERC20Token",
      constructorArguments: [paymasterAddress],
    });
    console.log("Token verified.");
  } catch (error) {
    console.error("Token verification failed:", error);
  }

  console.log("Deployment completed.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
