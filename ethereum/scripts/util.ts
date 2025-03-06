import { Contract, Signer } from 'ethers';
import { artifacts, ethers, network } from 'hardhat';

export async function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export const ONE_ETHER = BigInt('1000000000000000000');

export function ensure(predicate: boolean, errorMessage: string): void {
  if (!predicate) {
    throw new Error(errorMessage);
  }
}

export function isBitSet(n: number, offset: number): boolean {
  return ((n >> offset) & 1) === 1;
}

export async function deployContractWithDeployer(
  deployer: Signer,
  contractName: string,
  args: unknown[],
  isSilent?: boolean,
): Promise<Contract> {
  if (!isSilent) {
    console.log(`>>> deploy contract: ${contractName} with (${args.length}) args:`, ...args);
  }

  const contractFactory = await ethers.getContractFactory(contractName, deployer);
  const contract = await contractFactory.deploy(...args);
  await contract.waitForDeployment();

  const contractAddr = await contract.getAddress();

  if (!isSilent) {
    console.log(`>> contract ${contractName} deployed with address ${contractAddr}`);
  }

  return new Contract(contractAddr, contract.interface, deployer);
}

export async function loadContract(contractName: string, contractAddr: string, deployer: Signer): Promise<Contract> {
  const artifact = await artifacts.readArtifact(contractName);
  return new Contract(contractAddr, artifact.abi, deployer);
}

export function safetyFactorFromString(rawString: string): bigint {
  return ethers.parseEther(rawString) / BigInt("1000000000");
}

export function rateFromString(rawString: string): bigint {
  return ethers.parseEther(rawString) / BigInt("1000000");
}

export function ratePerBlockFromString(rawRatePerYear: string, blockTime: number): bigint {
  const blocks = 365 * 24 * 3600 / blockTime;
  return rateFromString(rawRatePerYear) / BigInt(blocks);
}

export const chainId = async (): Promise<number> => {
  return network.config.chainId ?? await network.provider.send('net_version', []);
}

export const getTimestampFromDate = (date?: Date): number => {
  if (!date) {
    date = new Date();
  }
  return Math.floor(date.getTime() / 1000);
}
