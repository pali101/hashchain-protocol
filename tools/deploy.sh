#!/bin/bash
# deploy.sh - Deploys MuPay or Multisig contracts to a specified network
# Usage: ./tools/deploy.sh <contract> <chain_id>
#   <contract>: mupay | multisig | both (default: both)
#   <chain_id>: 314159 (calibnet), 314 (mainnet), etc. (default: 314159)
#
# Example:
#   ./tools/deploy.sh mupay 314159
#   ./tools/deploy.sh multisig 314159
#   ./tools/deploy.sh both 314159

set -euo pipefail

CONTRACT="${1:-both}"
CHAIN_ID="${2:-314159}" # Default to calibnet

# Load environment variables from .env if present
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Set default RPC_URL if not set
if [ -z "${RPC_URL:-}" ]; then
  if [ "$CHAIN_ID" = "314159" ]; then
    export RPC_URL="https://api.calibration.node.glif.io/rpc/v1"
  elif [ "$CHAIN_ID" = "314" ]; then
    export RPC_URL="https://api.node.glif.io/rpc/v1"
  else
    echo "Error: RPC_URL must be set for CHAIN_ID $CHAIN_ID"
    exit 1
  fi
fi

if [ -z "${KEYSTORE:-}" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi
if [ -z "${PASSWORD:-}" ]; then
  echo "Error: PASSWORD is not set"
  exit 1
fi

ADDR=$(cast wallet address --keystore "$KEYSTORE" --password "$PASSWORD")
echo "Deploying from address $ADDR to chain $CHAIN_ID"
NONCE="$(cast nonce --rpc-url "$RPC_URL" "$ADDR")"

deploy_contract() {
  local contract_path="$1"
  local contract_name="$2"

  echo "Deploying $contract_name ($contract_path)"
  DEPLOYED_ADDRESS=$(
    forge create --rpc-url "$RPC_URL" \
      --keystore "$KEYSTORE" \
      --password "$PASSWORD" \
      --broadcast \
      --nonce $NONCE \
      --chain-id $CHAIN_ID \
      "$contract_path" \
      | grep "Deployed to" | awk '{print $3}'
  )

  if [ -z "$DEPLOYED_ADDRESS" ]; then
      echo "Error: Failed to extract $contract_name contract address"
      exit 1
  fi

  echo "$contract_name deployed at: $DEPLOYED_ADDRESS"
  NONCE=$((NONCE + 1)) # Increment nonce for next contract, if any
}

case "$CONTRACT" in
  mupay)
    deploy_contract "src/MuPay.sol:MuPay" "MuPay"
    ;;
  multisig)
    deploy_contract "src/Multisig_2of2.sol:Multisig" "Multisig"
    ;;
  *)
    echo "Invalid contract option: $CONTRACT"
    echo "Usage: $0 <mupay|multisig|both> [chain_id]"
    exit 1
    ;;
esac
echo "Deployment complete."