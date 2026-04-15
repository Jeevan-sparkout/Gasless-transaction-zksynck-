#!/usr/bin/env node
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const http = require('http');
const fs = require('fs');
const path = require('path');
const { Wallet, Provider, utils } = require('zksync-ethers');
const { ethers } = require('ethers');

const HOST = process.env.RELAYER_HOST || '127.0.0.1';
const PORT = Number(process.env.RELAYER_PORT || 8787);
const RPC_URL = process.env.ZKRPC || 'https://sepolia.era.zksync.dev';
const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY;

if (!PRIVATE_KEY) {
  console.error('Missing WALLET_PRIVATE_KEY in .env');
  process.exit(1);
}

const provider = new Provider(RPC_URL);
const relayer = new Wallet(PRIVATE_KEY, provider);

const TOKEN_IFACE = new ethers.Interface([
  'function decimals() view returns (uint8)',
  'function getFreeTokens(uint256 amount)',
  'function transfer(address to, uint256 amount) returns (bool)'
]);
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8'
};

async function sendSponsored({ tokenAddress, paymasterAddress, data, gasLimit }) {
  const gasPrice = await provider.getGasPrice();
  const txReq = {
    type: 113,
    from: relayer.address,
    to: tokenAddress,
    data,
    gasLimit: BigInt(gasLimit),
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

  const tx = await relayer.sendTransaction(txReq);
  const receipt = await tx.wait();
  if (!receipt || receipt.status !== 1) {
    throw new Error('Transaction failed');
  }
  return tx.hash;
}

function sendJson(res, status, obj) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  });
  res.end(JSON.stringify(obj));
}

function serveStatic(req, res) {
  let reqPath = req.url.split('?')[0];
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';
  const filePath = path.join(__dirname, reqPath);
  if (!filePath.startsWith(__dirname)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
      });
      res.end();
      return;
    }

    if (req.method === 'POST' && req.url === '/api/relayer-mint') {
      let raw = '';
      req.on('data', (chunk) => {
        raw += chunk;
        if (raw.length > 1_000_000) req.destroy();
      });

      req.on('end', async () => {
        try {
          const body = JSON.parse(raw || '{}');
          const tokenAddress = String(body.tokenAddress || '').trim();
          const paymasterAddress = String(body.paymasterAddress || '').trim();
          const recipient = String(body.recipient || '').trim();
          const amountHuman = String(body.amountHuman || '1').trim();
          const gasLimit = String(body.gasLimit || '1900000').trim();

          if (!ethers.isAddress(tokenAddress)) throw new Error('Invalid tokenAddress');
          if (!ethers.isAddress(paymasterAddress)) throw new Error('Invalid paymasterAddress');
          if (!ethers.isAddress(recipient)) throw new Error('Invalid recipient');

          const tokenRead = new ethers.Contract(tokenAddress, TOKEN_IFACE.fragments, provider);
          const decimals = await tokenRead.decimals();
          const amountWei = ethers.parseUnits(amountHuman, Number(decimals));
          if (amountWei <= 0n) throw new Error('Amount must be > 0');

          const mintData = TOKEN_IFACE.encodeFunctionData('getFreeTokens', [amountWei]);
          const mintTxHash = await sendSponsored({
            tokenAddress,
            paymasterAddress,
            data: mintData,
            gasLimit
          });

          const transferData = TOKEN_IFACE.encodeFunctionData('transfer', [recipient, amountWei]);
          const transferTxHash = await sendSponsored({
            tokenAddress,
            paymasterAddress,
            data: transferData,
            gasLimit
          });

          sendJson(res, 200, {
            ok: true,
            relayer: relayer.address,
            mintTxHash,
            transferTxHash
          });
        } catch (err) {
          sendJson(res, 400, { ok: false, error: err.message || String(err) });
        }
      });
      return;
    }

    if (req.method === 'GET') {
      serveStatic(req, res);
      return;
    }

    sendJson(res, 405, { ok: false, error: 'Method not allowed' });
  } catch (err) {
    sendJson(res, 500, { ok: false, error: err.message || String(err) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Relayer web server running at http://${HOST}:${PORT}`);
  console.log(`Relayer signer: ${relayer.address}`);
  console.log(`RPC: ${RPC_URL}`);
});
