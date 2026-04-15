#!/usr/bin/env node
require('dotenv').config();

const { Wallet, Provider, utils } = require('zksync-ethers');
const { ethers } = require('ethers');

async function main() {
  const rpcUrl = process.env.ZKRPC || 'https://sepolia.era.zksync.dev';
  const privateKey = process.env.WALLET_PRIVATE_KEY;

  if (!privateKey) {
    throw new Error('Missing WALLET_PRIVATE_KEY in .env');
  }

  const tokenAddress = process.argv[2] || '0x687600738C17e38641b6a850C6728D086fEeF2b4';
  const paymasterAddress = process.argv[3] || '0xE7526a8967568214b77e19D25b5B91F640055420';
  const amountHuman = process.argv[4] || '1';
  const gasLimitArg = process.argv[5] || '1900000';

  const provider = new Provider(rpcUrl);
  const wallet = new Wallet(privateKey, provider);

  const iface = new ethers.Interface([
    'function getFreeTokens(uint256 amount)',
    'function decimals() view returns (uint8)',
    'function balanceOf(address account) view returns (uint256)'
  ]);

  const tokenRead = new ethers.Contract(tokenAddress, iface.fragments, provider);
  const decimals = await tokenRead.decimals();
  const amount = ethers.parseUnits(amountHuman, decimals);
  const data = iface.encodeFunctionData('getFreeTokens', [amount]);

  const balanceBefore = await tokenRead.balanceOf(wallet.address);
  const gasPrice = await provider.getGasPrice();

  const txReq = {
    type: 113,
    from: wallet.address,
    to: tokenAddress,
    data,
    gasLimit: BigInt(gasLimitArg),
    maxFeePerGas: gasPrice,
    maxPriorityFeePerGas: 0,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
      paymasterParams: utils.getPaymasterParams(paymasterAddress, {
        type: 'General',
        innerInput: new Uint8Array()
      })
    }
  };

  const tx = await wallet.sendTransaction(txReq);
  const receipt = await tx.wait();
  const balanceAfter = await tokenRead.balanceOf(wallet.address);

  console.log(JSON.stringify({
    rpcUrl,
    tokenAddress,
    paymasterAddress,
    caller: wallet.address,
    amount: amount.toString(),
    txHash: tx.hash,
    blockNumber: receipt.blockNumber,
    status: receipt.status,
    gasLimit: txReq.gasLimit.toString(),
    balanceBefore: balanceBefore.toString(),
    balanceAfter: balanceAfter.toString()
  }, null, 2));
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
