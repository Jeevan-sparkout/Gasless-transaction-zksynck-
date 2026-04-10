import { Wallet, Provider, utils } from "zksync-ethers";
import * as ethers from "ethers";
import dotenv from "dotenv";

dotenv.config();

// Load environment variables
const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";
const L1_RPC_URL = process.env.RPC ; // Default to a public one if RPC is not set
const L2_RPC_URL = process.env.ZKRPC; // zkSync Era Sepolia

if (!PRIVATE_KEY) {
  throw new Error("WALLET_PRIVATE_KEY is not set in .env file");
}

async function main() {
  // Initialize providers
  const l1Provider = new ethers.JsonRpcProvider(L1_RPC_URL);
  const l2Provider = new Provider(L2_RPC_URL);

  // Initialize wallet
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  console.log(`Using wallet address: ${wallet.address}`);

  // Check balances
  const l1Balance = await l1Provider.getBalance(wallet.address);
  const l2Balance = await l2Provider.getBalance(wallet.address);

  console.log(`L1 (Sepolia) Balance: ${ethers.formatEther(l1Balance)} ETH`);
  console.log(`L2 (zkSync Sepolia) Balance: ${ethers.formatEther(l2Balance)} ETH`);

  if (l1Balance < ethers.parseEther("0.01")) {
    console.error("Insufficient L1 balance to bridge.");
    return;
  }

  // Amount to bridge
  const amountToBridge = ethers.parseEther("0.05"); // 0.05 ETH
  console.log(`Bridging ${ethers.formatEther(amountToBridge)} ETH to zkSync Era Sepolia...`);

  // Deposit ETH to L2
  const depositHandle = await wallet.deposit({
    token: utils.ETH_ADDRESS,
    amount: amountToBridge,
  });

  console.log(`Deposit transaction hash: ${depositHandle.hash}`);
  console.log("Waiting for deposit to be finalized on L2 (can take up to 15-20 minutes)...");

  // Wait for the deposit to be finalized on L2
  const receipt = await depositHandle.wait();
  console.log("Deposit finalized!");
  
  const newL2Balance = await l2Provider.getBalance(wallet.address);
  console.log(`New L2 (zkSync Sepolia) Balance: ${ethers.formatEther(newL2Balance)} ETH`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
