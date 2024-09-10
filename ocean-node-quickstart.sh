#!/usr/bin/env bash

#
# Copyright (c) 2024 Ocean Protocol contributors
# SPDX-License-Identifier: Apache-2.0
#

validate_hex() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "The private key seems invalid, exiting ..."
    exit 1
  fi
}

validate_address() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Invalid wallet address, exiting!"
    exit 1
  fi
}

validate_port() {
  if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -le 1024 ] || [ "$1" -ge 65535 ]]; then
    echo "Invalid port number, it must be between 1024 and 65535."
    exit 1
  fi
}

validate_ip_or_fqdn() {
  local input=$1

  if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r -a octets <<< "$input"
    for octet in "${octets[@]}"; do
      if (( octet < 0 || octet > 255 )); then
        echo "Invalid IPv4 address. Each octet must be between 0 and 255."
        return 1
      fi
    done

    if [[ "$input" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^169\.254\.|^100\.64\.|^198\.51\.100\.|^203\.0\.113\.|^224\.|^240\. ]]; then
      echo "The provided IP address belongs to a private or non-routable range and might not be accessible from other nodes."
      return 1
    fi
  elif [[ "$input" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    return 0
  else
    echo "Invalid input, must be a valid IPv4 address or FQDN."
    return 1
  fi

  return 0
}

# Generate or use default private key
echo "Generating Private Key..."
output=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n' | awk '{print "0x" $0}')
PRIVATE_KEY=$(echo "$output")
validate_hex "$PRIVATE_KEY"
echo -e "Using Private Key: \e[1;31m$PRIVATE_KEY\e[0m"

# Use default wallet address
ALLOWED_ADMINS="0x0000000000000000000000000000000000000000"
validate_address "$ALLOWED_ADMINS"
echo -e "Using default wallet address: \e[1;31m$ALLOWED_ADMINS\e[0m"

# Default port values
HTTP_API_PORT=8000
P2P_ipV4BindTcpPort=9000
P2P_ipV4BindWsPort=9001
P2P_ipV6BindTcpPort=9002
P2P_ipV6BindWsPort=9003

validate_port "$HTTP_API_PORT"
validate_port "$P2P_ipV4BindTcpPort"
validate_port "$P2P_ipV4BindWsPort"
validate_port "$P2P_ipV6BindTcpPort"
validate_port "$P2P_ipV6BindWsPort"

# Default IP/FQDN or leave empty
P2P_ANNOUNCE_ADDRESS=""

if [ -n "$P2P_ANNOUNCE_ADDRESS" ]; then
  validate_ip_or_fqdn "$P2P_ANNOUNCE_ADDRESS"
  if [ $? -ne 0 ]; then
    echo "Invalid address. Exiting!"
    exit 1
  fi

  if [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # IPv4
    P2P_ANNOUNCE_ADDRESSES='["/ip4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_ipV4BindTcpPort'", "/ip4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_ipV4BindWsPort'"]'
  elif [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    # FQDN
    P2P_ANNOUNCE_ADDRESSES='["/dns4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_ipV4BindTcpPort'", "/dns4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_ipV4BindWsPort'"]'
  fi
else
  P2P_ANNOUNCE_ADDRESSES=''
  echo "No P2P announce address provided. The Ocean Node might not be accessible from other nodes."
fi

cat <<EOF > docker-compose.yml
services:
  ocean-node:
    image: oceanprotocol/ocean-node:latest
    pull_policy: always
    container_name: ocean-node
    restart: on-failure
    ports:
      - "$HTTP_API_PORT:$HTTP_API_PORT"
      - "$P2P_ipV4BindTcpPort:$P2P_ipV4BindTcpPort"
      - "$P2P_ipV4BindWsPort:$P2P_ipV4BindWsPort"
      - "$P2P_ipV6BindTcpPort:$P2P_ipV6BindTcpPort"
      - "$P2P_ipV6BindWsPort:$P2P_ipV6BindWsPort"
    environment:
      PRIVATE_KEY: '$PRIVATE_KEY'
      RPCS: '{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'
      DB_URL: 'http://typesense:8108/?apiKey=xyz'
      IPFS_GATEWAY: 'https://ipfs.io/'
      ARWEAVE_GATEWAY: 'https://arweave.net/'
      INTERFACES: '["HTTP","P2P"]'
      ALLOWED_ADMINS: '["$ALLOWED_ADMINS"]'
      HTTP_API_PORT: '$HTTP_API_PORT'
      P2P_ENABLE_IPV4: 'true'
      P2P_ENABLE_IPV6: 'false'
      P2P_ipV4BindAddress: '0.0.0.0'
      P2P_ipV4BindTcpPort: '$P2P_ipV4BindTcpPort'
      P2P_ipV4BindWsPort: '$P2P_ipV4BindWsPort'
      P2P_ipV6BindAddress: '::'
      P2P_ipV6BindTcpPort: '$P2P_ipV6BindTcpPort'
      P2P_ipV6BindWsPort: '$P2P_ipV6BindWsPort'
      P2P_ANNOUNCE_ADDRESSES: '$P2P_ANNOUNCE_ADDRESSES'
    networks:
      - ocean_network
    depends_on:
      - typesense

  typesense:
    image: typesense/typesense:26.0
    container_name: typesense
    ports:
      - "8108:8108"
    networks:
      - ocean_network
    volumes:
      - typesense_data:/data
    command: --api-key=xyz

networks:
  ocean_network:
    driver: bridge

volumes:
  typesense_data:
EOF

echo "docker-compose.yml has been generated."
echo "You can now run 'docker-compose up -d' to start the Ocean Node."
