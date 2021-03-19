const { config: dotenvConfig } = require('dotenv');
const { resolve } = require('path');
require('@nomiclabs/hardhat-waffle');
require('hardhat-gas-reporter');

dotenvConfig({ path: resolve(__dirname, './.env') });

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

let INFURA_PROJECT_ID;
if (!process.env.INFURA_PROJECT_ID) {
  throw new Error('Please set your INFURA_PROJECT_ID in a .env file');
} else {
  INFURA_PROJECT_ID = process.env.INFURA_PROJECT_ID;
}

let RINKEBY_PRIVATE_KEY;
if (!process.env.RINKEBY_PRIVATE_KEY) {
  throw new Error('Please set your RINKEBY_PRIVATE_KEY in a .env file');
} else {
  RINKEBY_PRIVATE_KEY = process.env.RINKEBY_PRIVATE_KEY;
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.6.7',
      },
    ],
  },
  networks: {
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${RINKEBY_PRIVATE_KEY}`],
    },
  },
};
