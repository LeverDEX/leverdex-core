import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';
import ERC20PresetMinterPauser from '@openzeppelin/contracts/build/contracts/ERC20PresetMinterPauser.json';

const MFI_ADDRESS = '0xAa4e3edb11AFa93c41db59842b29de64b72E355B';
const TOKEN_ACTIVATOR = 9;

const UNI_FACTORY_ADDRESS = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';

const UNI_INIT_CODE_HASH = '0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';

const tokensPerNetwork = {
  kovan: {
    //    USDT: USDT_ADDRESS,
    DAI: '0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa',
    WETH: '0xd0a1e359811322d97991e03f863a0c30c2cf029c'
    //    UNI: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
    //    MKR: "0xac94ea989f6955c67200dd67f0101e1865a560ea",
  },
  mainnet: {
    DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
    WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    UNI: '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984',
    MKR: '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2',
    USDT: '0xdAC17F958D2ee523a2206206994597C13D831ec7'
  },
  local: {}
};

enum AMMs {
  UNISWAP,
  SUSHISWAP
}

type TokenInitRecord = {
  exposureCap: number;
  lendingBuffer: number;
  incentiveWeight: number;
  liquidationTokenPath?: string[];
  ammPath?: AMMs[];
};
const tokenParams: { [tokenName: string]: TokenInitRecord } = {
  DAI: {
    exposureCap: 100000000,
    lendingBuffer: 10000,
    incentiveWeight: 5,
    liquidationTokenPath: ['DAI', 'WETH', 'USDT']
  },
  WETH: {
    exposureCap: 10000,
    lendingBuffer: 100,
    incentiveWeight: 5,
    liquidationTokenPath: ['WETH', 'USDT']
  },
  UNI: {
    exposureCap: 100000,
    lendingBuffer: 400,
    incentiveWeight: 5,
    liquidationTokenPath: ['UNI', 'WETH', 'USDT']
  },
  MKR: {
    exposureCap: 500,
    lendingBuffer: 80,
    incentiveWeight: 5,
    liquidationTokenPath: ['MKR', 'WETH', 'USDT']
  },
  USDT: {
    // TODO: take decimals out of exposure cap
    exposureCap: 1,
    lendingBuffer: 10000,
    incentiveWeight: 5
  },
  LOCALPEG: {
    exposureCap: 1000000,
    lendingBuffer: 10000,
    incentiveWeight: 5
  }
};

function encodeAMMPath(ammPath: AMMs[]) {
  const encoded = ethers.utils.hexlify(ammPath.map((amm: AMMs) => (amm == AMMs.UNISWAP ? 0 : 1)));
  console.log(encoded);
  return `${encoded}${'0'.repeat(64 + 2 - encoded.length)}`;
}

const deploy: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  getChainId,
  getUnnamedAccounts,
  network
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer, weth } = await getNamedAccounts();

  const DC = await deployments.get('DependencyController');
  const dc = await ethers.getContractAt('DependencyController', DC.address);

  ethers.utils.parseUnits('10000', 18);

  const networkName = network.live ? network.name : 'local';
  const peg = (await deployments.get('Peg')).address;

  //  const tokens = network.live ? tokensPerNetwork[networkName] : { LOCALPEG: peg };
  /*
  const tokens = network.live
    ? tokensPerNetwork[networkName]
    : tokensPerNetwork['mainnet'];
  */
  const tokens = network.live ? tokensPerNetwork[networkName] : tokensPerNetwork['mainnet'];

  const tokenAddresses = Object.values(tokens);
  const tokenNames = Object.keys(tokens);

  const exposureCaps = tokenNames.map(name => {
    return ethers.utils.parseUnits(`${tokenParams[name].exposureCap}`, 18);
  });

  const lendingBuffers = tokenNames.map(name => {
    return ethers.utils.parseUnits(`${tokenParams[name].lendingBuffer}`, 18);
  });
  const incentiveWeights = tokenNames.map(name => tokenParams[name].incentiveWeight);

  const liquidationTokens = tokenNames.map(name => {
    const tokenPath = tokenParams[name].liquidationTokenPath;
    if (network.name === 'mainnet' || !network.live) {
      // mainnet or forked mainnet
      return tokenPath ? tokenPath.map(tName => tokens[tName]) : [tokens[name], weth, peg];
    } else {
      return [tokens[name], peg];
    }
  });

  const liquidationAmms = tokenNames.map(name =>
    tokenParams[name].ammPath ? encodeAMMPath(tokenParams[name].ammPath) : ethers.utils.hexZeroPad('0x00', 32)
  );

  const Roles = await deployments.get('Roles');
  const roles = await ethers.getContractAt('Roles', Roles.address);

  const args = [
    roles.address,
    tokenAddresses,
    exposureCaps,
    lendingBuffers,
    incentiveWeights,
    liquidationAmms,
    liquidationTokens
  ];

  console.log(args);

  const TokenActivation = await deploy('TokenActivation', {
    from: deployer,
    args,
    log: true,
    skipIfAlreadyDeployed: true
  });

  // run if it hasn't self-destructed yet
  if ((await ethers.provider.getCode(TokenActivation.address)) !== '0x') {
    console.log(`Executing token activation ${TokenActivation.address} via dependency controller ${dc.address}`);
    const tx = await dc.executeAsOwner(TokenActivation.address);
    console.log(`ran ${TokenActivation.address} as owner, tx: ${tx.hash}`);
  }

  const TREASURY = '0xB3f923eaBAF178fC1BD8E13902FC5C61D3DdEF5B';
  //const TREASURY = '0xF9D89Dc506c55738379C44Dc27205fD6f68e1974';
  //const TREASURY = '0x16F3Fc1E4BA9d70f47387b902fa5d21020b5C6B5';
  // if we are impersonating, steal some crypto
  if (!network.live) {
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [TREASURY]
    });

    const signer = await ethers.provider.getSigner(TREASURY);
    let tx = await signer.sendTransaction({ to: deployer, value: ethers.utils.parseEther('10') });
    console.log(`Sending eth from treasury to ${deployer}:`);
    console.log(tx);

    const dai = await ethers.getContractAt(ERC20PresetMinterPauser.abi, tokens['DAI']);
    tx = await dai.connect(signer).transfer(deployer, ethers.utils.parseEther('200'));
    console.log(`Sending dai from treasury to ${deployer}:`);
    console.log(tx);

    // const usdt = await ethers.getContractAt(ERC20PresetMinterPauser.abi, tokens['USDT']);
    // tx = await usdt.connect(signer).transfer(deployer, ethers.utils.parseEther('50'));
    // console.log(`Sending usdt from treasury to ${deployer}:`);
    // console.log(tx);
  }
};

deploy.tags = ['TokenActivation', 'local'];
deploy.dependencies = ['DependencyController'];
export default deploy;
