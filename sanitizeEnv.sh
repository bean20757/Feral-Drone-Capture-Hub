
ENV_FILE=".env"
WORLD_ADDRESS="0x8a791620dd6260079bf849dc5567adc3f2fdc318"
CHAIN_ID="31337"
RPC_URL="http://127.0.0.1:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

#COLORS
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

function sanitize() {
    FILE_NAME=$1
    OS=$(uname)
    if [ "${OS:-}" = "Darwin" ]; then
      set -- -i ''
    else
      set -- -i
    fi
    sed "$@" "s/^PRIVATE_KEY=.*/PRIVATE_KEY=$PRIVATE_KEY/" "$FILE_NAME"
    sed "$@" "s/^WORLD_ADDRESS=.*/WORLD_ADDRESS=$WORLD_ADDRESS #Local World Address/" "$FILE_NAME"
    sed "$@" "s/^CHAIN_ID=.*/CHAIN_ID=$CHAIN_ID #Local Chain ID/" "$FILE_NAME"
    sed "$@" "s|^RPC_URL=.*|RPC_URL=$RPC_URL #Forked Anvil Forked Anvil Local RPC Url|" "$FILE_NAME"

    printf "\n%b[SANITIZED]%b file %b%s%b\n\n" "${GREEN}" "${RESET}" "${YELLOW}" "${FILE_NAME}" "${RESET}"
}

sanitize "smart-gate/packages/contracts/.env"
sanitize "smart-storage-unit/packages/contracts/.env"
sanitize "smart-turret/packages/contracts/.env"