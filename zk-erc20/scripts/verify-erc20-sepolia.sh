#!/usr/bin/env bash
set -euo pipefail

# Verifies MyERC20Token on ZKsync Era Sepolia using the exact build-info settings.
# Requires: jq, curl

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_INFO="$PROJECT_ROOT/artifacts-zk/build-info/06aeced8cd8d03a5bd2cdf2b37d89796.json"
FLAT_SOURCE="$PROJECT_ROOT/contracts/MyERC20Token_flat.sol"
TMP_DIR="$PROJECT_ROOT/tmp"

CONTRACT_ADDRESS="0x9932F47c8d14b144A22b5A2ba929648f0Ffc95B5"
CONTRACT_NAME="contracts/MyERC20Token_flat.sol:MyERC20Token"
VERIFY_URL="https://explorer.sepolia.era.zksync.dev/contract_verification"

COMPILER_SOLC_VERSION="zkVM-0.8.30-1.0.2"
COMPILER_ZKSOLC_VERSION="v1.5.15"
CONSTRUCTOR_ARGS="0x"
OPTIMIZATION_USED=true

mkdir -p "$TMP_DIR"

# Extract exact compiler settings from build-info
jq '.input.settings' "$BUILD_INFO" > "$TMP_DIR/erc20-settings.json"

# Build standard JSON input using the flattened source and extracted settings
jq -n --slurpfile settings "$TMP_DIR/erc20-settings.json" \
  --arg content "$(cat "$FLAT_SOURCE")" \
  '{language:"Solidity",sources:{"contracts/MyERC20Token_flat.sol":{content:$content}},settings:$settings[0]}' \
  > "$TMP_DIR/standard-json-input-erc20-flat.json"

# Build verification payload
jq -n --slurpfile sc "$TMP_DIR/standard-json-input-erc20-flat.json" \
  --arg contractAddress "$CONTRACT_ADDRESS" \
  --arg contractName "$CONTRACT_NAME" \
  --arg compilerSolcVersion "$COMPILER_SOLC_VERSION" \
  --arg compilerZksolcVersion "$COMPILER_ZKSOLC_VERSION" \
  --arg constructorArguments "$CONSTRUCTOR_ARGS" \
  --argjson optimizationUsed "$OPTIMIZATION_USED" \
  '{contractAddress:$contractAddress,
    sourceCode:$sc[0],
    codeFormat:"solidity-standard-json-input",
    contractName:$contractName,
    compilerSolcVersion:$compilerSolcVersion,
    compilerZksolcVersion:$compilerZksolcVersion,
    constructorArguments:$constructorArguments,
    optimizationUsed:$optimizationUsed}' \
  > "$TMP_DIR/verify-payload-erc20-flat.json"

# Submit verification
VERIFY_ID=$(curl -sS -X POST -H 'Content-Type: application/json' --data @"$TMP_DIR/verify-payload-erc20-flat.json" "$VERIFY_URL")

if [[ -z "$VERIFY_ID" ]]; then
  echo "Verification request failed: empty response"
  exit 1
fi

echo "Verification ID: $VERIFY_ID"

# Check status
STATUS=$(curl -sS "$VERIFY_URL/$VERIFY_ID")

echo "Status: $STATUS"
