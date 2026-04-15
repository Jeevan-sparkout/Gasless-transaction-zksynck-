# zk-erc20 (zkSync Era Sepolia)

ERC20 + paymaster example project on zkSync Era Sepolia with:
- `MyERC20Token` token contract (`getFreeTokens(uint256)` mint function)
- `GaslessSponsoredPaymaster` paymaster contract
- local backend-relayer UI for gasless mint UX

## Contracts (current deployment)

- `MyERC20Token`: `0x687600738C17e38641b6a850C6728D086fEeF2b4`
- `GaslessSponsoredPaymaster`: `0xE7526a8967568214b77e19D25b5B91F640055420`

## Prerequisites

- Node.js 18+
- npm
- funded paymaster balance on zkSync Era Sepolia
- `.env` with:

```bash
WALLET_PRIVATE_KEY=0x...
# optional
RPC_URL=https://sepolia.era.zksync.dev
RELAYER_HOST=127.0.0.1
RELAYER_PORT=8787
```

## Core Commands

- `npm run compile`
- `npm run deploy`
- `npm run relayer-ui`

## Backend Relayer UI (recommended for current wallet limitations)

Some wallet extensions reject zkSync EIP-712 envelope `0x71` directly in browser contract-write UIs.  
This project includes a backend relayer flow that avoids that limitation.

### Start UI + relayer server

```bash
cd /home/sparkout/Desktop/zksynck/zk-erc20
npm run relayer-ui
```

Open:

- `http://127.0.0.1:8787/`

### UI flow

1. Click `Connect Wallet`
2. Set token/paymaster/amount/recipient/gas limit
3. Click `Relayer Mint`

What happens:

1. Backend signs sponsored `getFreeTokens(amount)` using relayer wallet from `.env`
2. Backend signs sponsored `transfer(recipient, amount)` to deliver minted tokens
3. UI shows both tx hashes

## Scripts

- `scripts/get-free-tokens-sponsored.js`  
  Direct sponsored mint from CLI (no browser dependency). Useful fallback for debugging.

- `scripts/deploy-gasless-and-token.ts`  
  Deploy paymaster + token flow.

- `scripts/verify-zksync-contract.sh`  
  Explorer verification helper.

## Notes

- `GaslessSponsoredPaymaster.maxGasLimitPerTx` is enforced. Keep tx gas limit under that value.
- If paymaster balance is low, sponsorship fails in validation.
- If you change wallet/private key in `.env`, restart the relayer server.

## License

MIT. See [LICENSE](./LICENSE).
