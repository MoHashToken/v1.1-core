module.exports = {

  dashboard: {
    port: 24012,
  },

  networks: {

    // ganache-cli for devtest
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      websockets: true,
      gas: 4000000,
    },
    ropsten: {
      // provider: function() {
      //   return new HDWalletProvider(mnemonic, "https://ropsten.infura.io/v3/YOUR-PROJECT-ID");
      // },
      network_id: 3,
      networkCheckTimeout: 999999,
      timeoutBlocks: 4000,
      gas: 4000000, //make sure this gas allocation isn't over 4M, which is the max
    },
    live: {
      host: "178.25.19.88", // Random IP for example purposes (do not use)
      port: 80,
      network_id: 1,        // Ethereum public network
      // optional config values:
      // gas                  -
      // gasPrice             - use gas and gasPrice if creating type 0 transactions
      // maxFeePerGas         -
      // maxPriorityFeePerGas - use maxFeePerGas and maxPriorityFeePerGas if creating type 2 transactions (https://eips.ethereum.org/EIPS/eip-1559)
      // from - default address to use for any transaction Truffle makes during migrations
      // provider - web3 provider instance Truffle should use to talk to the Ethereum network.
      //          - function that returns a web3 provider instance (see below.)
      //          - if specified, host and port are ignored.
      // skipDryRun: - true if you don't want to test run the migration locally before the actual migration (default is false)
      // confirmations: - number of confirmations to wait between deployments (default: 0)
      // timeoutBlocks: - if a transaction is not mined, keep waiting for this number of blocks (default is 50)
      // deploymentPollingInterval: - duration between checks for completion of deployment transactions
      // disableConfirmationListener: - true to disable web3's confirmation listener
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    enableTimeouts: true,
    timeout: 120000,
    useColors: true,
  },

  // Configure your compilers
  compilers: {

    solc: {
      version: "0.8.2",
      docker: false,
      parser: "solcjs",
      settings: {          // See the solidity docs for advice about optimization and evmVersion
       optimizer: {
         enabled: true,
         runs: 200
       },
       // evmVersion: "byzantium"
      }
    },
  },

  db: {
    enabled: false,
  },
};
