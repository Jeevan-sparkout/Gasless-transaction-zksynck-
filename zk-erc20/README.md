# zk-erc20

![zkSync Era](https://img.shields.io/badge/network-zkSync%20Era%20Sepolia-8c8dfc?style=flat-square)
![Gasless](https://img.shields.io/badge/transactions-gasless-31c48d?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

Use this project to receive **ZK Spark Token (ZKS)** on zkSync Era Sepolia without paying gas from your wallet.

The project already has a token and paymaster configured. You do **not** need to deploy a new contract or hold ETH in the wallet receiving tokens.

## What happens

```text
Your wallet -> local relayer -> sponsored mint -> sponsored transfer -> your wallet receives ZKS
```

The relayer uses the project's funded paymaster to cover the transaction fees. Your connected wallet is only used to choose the recipient address.

## Run the project

### 1. Install dependencies

```bash
npm ci
```

### 2. Configure the relayer

Create your local environment file:

```bash
cp .env.example .env
```

Set the wallet private key used by the local relayer:

```dotenv
# Required: relayer signer used to submit sponsored transactions
WALLET_PRIVATE_KEY=0x...

# Optional
ZKRPC=https://sepolia.era.zksync.dev
RELAYER_HOST=127.0.0.1
RELAYER_PORT=8787
```

This is the relayer's key, not the end user's wallet key. Keep it private and never commit `.env`.

> For a gasless transaction to succeed, the configured relayer and the existing paymaster must have sufficient zkSync Era Sepolia ETH. The receiving wallet does not need ETH.

### 3. Start the app

```bash
npm run relayer-ui
```

Open [http://127.0.0.1:8787/](http://127.0.0.1:8787/).

## Make a gasless transaction

1. Open the app in a browser with MetaMask, Rabby, or another zkSync-compatible wallet.
2. Click **Connect Wallet**.
3. Approve switching to **zkSync Era Sepolia** if prompted.
4. Confirm your wallet address is shown as the recipient, or enter another recipient address.
5. Leave the prefilled token and paymaster addresses unchanged.
6. Enter the number of ZKS tokens to receive.
7. Click **Mint Tokens**.

The app submits the sponsored transactions through the backend relayer and returns both transaction hashes. No ETH is taken from the connected wallet.

## Preconfigured Sepolia contracts

| Contract | Address |
| --- | --- |
| ZK Spark Token (`ZKS`) | [`0x687600738C17e38641b6a850C6728D086fEeF2b4`](https://sepolia.explorer.zksync.io/address/0x687600738C17e38641b6a850C6728D086fEeF2b4) |
| Gasless Sponsored Paymaster | [`0xE7526a8967568214b77e19D25b5B91F640055420`](https://sepolia.explorer.zksync.io/address/0xE7526a8967568214b77e19D25b5B91F640055420) |

The UI starts with these addresses already filled in.

## Useful commands

| Command | Purpose |
| --- | --- |
| `npm run relayer-ui` | Run the gasless transaction UI and backend relayer |
| `npm run compile` | Compile contracts locally |
| `npm test` | Run the local contract tests |
| `node scripts/get-free-tokens-sponsored.js` | Send a sponsored mint from the relayer wallet without the browser UI |

### Gasless CLI mint

Use this only when the relayer environment is configured. It mints tokens to the wallet in `WALLET_PRIVATE_KEY`:

```bash
node scripts/get-free-tokens-sponsored.js \
  0x687600738C17e38641b6a850C6728D086fEeF2b4 \
  0xE7526a8967568214b77e19D25b5B91F640055420 \
  1 \
  1900000
```

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `Missing WALLET_PRIVATE_KEY` | Add the relayer's development private key to `.env`, then restart the server. |
| `Paymaster balance might not be enough` | The paymaster or relayer needs more zkSync Era Sepolia ETH to continue sponsoring transactions. |
| Wallet cannot connect | Unlock the extension and switch to zkSync Era Sepolia (chain ID `300`). |
| Mint transaction fails | Check that the token/paymaster fields use the preconfigured addresses and gas limit stays at or below `2,000,000`. |
| The page does not open | Keep `npm run relayer-ui` running and visit `http://127.0.0.1:8787/`. |

## Security note

The relayer server is for local development. Do not expose it publicly, and do not use a wallet containing valuable funds.

## License

MIT. See [LICENSE](./LICENSE).
