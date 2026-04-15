#!/usr/bin/env bash
set -euo pipefail

# Verify a ZKsync Era contract on the block explorer.
# Requirements: jq, curl
#
# Supports:
# - Explicit flags: --address, --build-info, --contract-name, --flat-source, --constructor-args
# - Auto mode: --auto (derive address + contract from deployments-zk)
#
# Examples:
#   bash scripts/verify-zksync-contract.sh --address 0x... --build-info artifacts-zk/build-info/xxxx.json \
#     --contract-name contracts/MyERC20Token.sol:MyERC20Token --flat-source contracts/MyERC20Token_flat.sol
#
#   bash scripts/verify-zksync-contract.sh --auto --deployment-network ZKsyncEraSepolia \
#     --deployment-contract MyERC20Token

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_URL_DEFAULT="https://explorer.sepolia.era.zksync.dev/contract_verification"
TMP_DIR="$PROJECT_ROOT/tmp"

ADDRESS=""
BUILD_INFO=""
CONTRACT_NAME=""
FLAT_SOURCE=""
CONSTRUCTOR_ARGS="0x"
VERIFY_URL="$VERIFY_URL_DEFAULT"
AUTO_MODE=false
DEPLOYMENT_NETWORK="ZKsyncEraSepolia"
DEPLOYMENT_CONTRACT=""

usage() {
  cat <<'USAGE'
Usage:
  verify-zksync-contract.sh [--address ADDR] [--build-info FILE] [--contract-name NAME] [--flat-source FILE]
                            [--constructor-args HEX]
                            [--verify-url URL]
  verify-zksync-contract.sh --auto [--deployment-network NAME] --deployment-contract NAME [--verify-url URL]

Flags:
  --address              Contract address to verify (0x...)
  --build-info           Build-info JSON file path (artifacts-zk/build-info/*.json)
  --contract-name        Fully qualified contract name (e.g. contracts/My.sol:My)
  --flat-source          Flattened source file path (if needed by explorer)
  --constructor-args     Hex-encoded constructor args (0x...)
  --verify-url           Verification endpoint (default: Sepolia)

Auto mode:
  --auto                 Read address & contract from deployments-zk
  --deployment-network   Network folder under deployments-zk (default: ZKsyncEraSepolia)
  --deployment-contract  Contract name folder under deployments-zk/.../contracts/*
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) ADDRESS="$2"; shift 2 ;;
    --build-info) BUILD_INFO="$2"; shift 2 ;;
    --contract-name) CONTRACT_NAME="$2"; shift 2 ;;
    --flat-source) FLAT_SOURCE="$2"; shift 2 ;;
    --constructor-args) CONSTRUCTOR_ARGS="$2"; shift 2 ;;
    --verify-url) VERIFY_URL="$2"; shift 2 ;;
    --auto) AUTO_MODE=true; shift ;;
    --deployment-network) DEPLOYMENT_NETWORK="$2"; shift 2 ;;
    --deployment-contract) DEPLOYMENT_CONTRACT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown flag: $1" ;;
  esac
done

mkdir -p "$TMP_DIR"

if $AUTO_MODE; then
  [[ -z "$DEPLOYMENT_CONTRACT" ]] && die "--deployment-contract is required in --auto mode"
  DEPLOYMENTS_DIR="$PROJECT_ROOT/deployments-zk/$DEPLOYMENT_NETWORK/contracts"
  [[ -d "$DEPLOYMENTS_DIR" ]] || die "Deployments directory not found: $DEPLOYMENTS_DIR"

  # Find the first deployment JSON for the contract.
  DEPLOY_JSON="$(rg --files -g "$DEPLOYMENT_CONTRACT.sol/*.json" "$DEPLOYMENTS_DIR" | head -n 1 || true)"
  [[ -n "$DEPLOY_JSON" ]] || die "No deployment JSON found for $DEPLOYMENT_CONTRACT in $DEPLOYMENTS_DIR"

  ADDRESS="$(jq -r '.entries[0].address // empty' "$DEPLOY_JSON")"
  [[ -n "$ADDRESS" ]] || die "Address not found in deployment JSON: $DEPLOY_JSON"

  CONTRACT_NAME="$(jq -r '.sourceName + ":" + .contractName' "$DEPLOY_JSON")"
  [[ -n "$CONTRACT_NAME" ]] || die "Contract name not found in deployment JSON: $DEPLOY_JSON"

  # Derive a flat source path if present
  FLAT_SOURCE_GUESS="$PROJECT_ROOT/contracts/${DEPLOYMENT_CONTRACT}_flat.sol"
  if [[ -f "$FLAT_SOURCE_GUESS" ]]; then
    FLAT_SOURCE="$FLAT_SOURCE_GUESS"
  fi

  # Auto-detect build-info if not provided.
  if [[ -z "$BUILD_INFO" ]]; then
    BUILD_INFO="$(rg --files -g '*.json' "$PROJECT_ROOT/artifacts-zk/build-info" | while read -r f; do
      if jq -e --arg src "${CONTRACT_NAME%%:*}" --arg name "${CONTRACT_NAME##*:}" \
        '.output.contracts[$src][$name] != null' "$f" >/dev/null 2>&1; then
        echo "$f"
        break
      fi
    done)"
  fi
fi

[[ -n "$ADDRESS" ]] || die "--address is required (or use --auto)"
[[ -n "$BUILD_INFO" ]] || die "--build-info is required (or use --auto to auto-detect)"
[[ -n "$CONTRACT_NAME" ]] || die "--contract-name is required (or use --auto)"
[[ -f "$BUILD_INFO" ]] || die "Build-info file not found: $BUILD_INFO"
[[ "$CONSTRUCTOR_ARGS" == 0x* ]] || die "--constructor-args must start with 0x"

# Extract compiler settings and versions from build-info
jq '.input.settings' "$BUILD_INFO" > "$TMP_DIR/compiler-settings.json"

COMPILER_SOLC_VERSION="$(jq -r '.solcVersion' "$BUILD_INFO")"
[[ -n "$COMPILER_SOLC_VERSION" && "$COMPILER_SOLC_VERSION" != "null" ]] || die "solcVersion not found in build-info"

ZK_VERSION="$(
  jq -r '
    .output.contracts
    | to_entries[]
    | .value
    | to_entries[]
    | .value.metadata
    | (
        if type == "string" then (fromjson? // {}) else . end
      )
    | .zk_version // empty
  ' "$BUILD_INFO" | head -n 1
)"
[[ -n "$ZK_VERSION" ]] || die "zk_version not found in build-info metadata"

COMPILER_ZKSOLC_VERSION="v${ZK_VERSION}"

# Build standard JSON input. Prefer flattened source if provided.
if [[ -n "$FLAT_SOURCE" ]]; then
  [[ -f "$FLAT_SOURCE" ]] || die "Flattened source file not found: $FLAT_SOURCE"
  jq -n --slurpfile settings "$TMP_DIR/compiler-settings.json" \
    --arg content "$(cat "$FLAT_SOURCE")" \
    --arg flatPath "$(basename "$FLAT_SOURCE")" \
    '{language:"Solidity",sources:{($flatPath):{content:$content}},settings:$settings[0]}' \
    > "$TMP_DIR/standard-json-input.json"

  # If flat source used, contract name should match that file name.
  if [[ "$CONTRACT_NAME" != *":"* ]]; then
    die "contract-name must be fully qualified, e.g. contracts/My.sol:My"
  fi
else
  # Use full compiler input from build-info (includes imports)
  jq '.input' "$BUILD_INFO" > "$TMP_DIR/standard-json-input.json"
fi

# Build verification payload (match hardhat-zksync-verify fields)
jq -n --slurpfile sc "$TMP_DIR/standard-json-input.json" \
  --arg contractAddress "$ADDRESS" \
  --arg contractName "$CONTRACT_NAME" \
  --arg compilerSolcVersion "$COMPILER_SOLC_VERSION" \
  --arg compilerZksolcVersion "$COMPILER_ZKSOLC_VERSION" \
  --arg constructorArguments "$CONSTRUCTOR_ARGS" \
  --argjson optimizationUsed "true" \
  '{contractAddress:$contractAddress,
    sourceCode:$sc[0],
    codeFormat:"solidity-standard-json-input",
    contractName:$contractName,
    compilerSolcVersion:$compilerSolcVersion,
    compilerZksolcVersion:$compilerZksolcVersion,
    constructorArguments:$constructorArguments,
    optimizationUsed:$optimizationUsed}' \
  > "$TMP_DIR/verify-payload.json"

# Submit verification
VERIFY_ID="$(curl -sS -X POST -H 'Content-Type: application/json' --data @"$TMP_DIR/verify-payload.json" "$VERIFY_URL")"
[[ -n "$VERIFY_ID" ]] || die "Verification request failed: empty response"

echo "Verification ID: $VERIFY_ID"

# Check status
STATUS="$(curl -sS "$VERIFY_URL/$VERIFY_ID")"
echo "Status: $STATUS"
