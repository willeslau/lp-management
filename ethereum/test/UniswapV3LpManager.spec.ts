import { Contract, Signer, ZeroAddress } from "ethers";
import { ethers, network } from "hardhat";
import { deployUniswapFactory, UniswapPool } from "./uniswapV3Deployer";
import { deployContractWithDeployer, loadContract } from "../scripts/util";
import { DeltaNeutral } from "../scripts/DeltaNeutral";
import { expect } from "chai";
import { Token } from "@uniswap/sdk-core";
import JSBI from "jsbi";

interface TestSetup {
  owner: Signer;
  operator: DeltaNeutral;
  uniswap: UniswapPool;
}

async function setupTest(): Promise<TestSetup> {
  const [contractOwner] = await ethers.getSigners();

  const config: any  = {};

  // ==============================================
  // =========== setup uniswap related ============
  // ==============================================
  let uniswap;
  let nonfungiblePositionMananger;

  let tokenA;
  let tokenB;
  {
    tokenA = await deployContractWithDeployer(
      contractOwner,
      "TestToken",
      [
        "ETH",
        "ETH",
        await contractOwner.getAddress(),
        ethers.parseEther("100000000000"),
      ],
      true
    );
    tokenB = await deployContractWithDeployer(
      contractOwner,
      "TestToken",
      [
        "UNI",
        "UNI",
        await contractOwner.getAddress(),
        ethers.parseEther("100000000000"),
      ],
      true
    );
    const fee = 3000;
    const initialPriceSqrtQ96 = 4436738577262596212334852517n;
    uniswap = await deployUniswapFactory(
      contractOwner,
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      fee,
      initialPriceSqrtQ96
    );
    nonfungiblePositionMananger = await deployContractWithDeployer(
      contractOwner,
      "MockedNonFungibleMananger",
      [await uniswap.factory.getAddress(), ZeroAddress],
      true,
    );
    config.nonfungiblePositionMananger = await nonfungiblePositionMananger.getAddress();
  }

  // ==============================================
  // =========== setup uniswap related ============
  // ==============================================

  const operatorContract = await DeltaNeutral.deploy(config, contractOwner);
  const operator = await DeltaNeutral.fromPool(network.config.chainId!, await uniswap.pool.getAddress(), await operatorContract.getAddress(), contractOwner);

  const amount0Desired = ethers.parseEther("312500");
  const amount1Desired = ethers.parseEther("1000");
  const token0 = await loadContract("IERC20", uniswap.token0, contractOwner);
  const token1 = await loadContract("IERC20", uniswap.token1, contractOwner);
  token0.approve(await nonfungiblePositionMananger.getAddress(), amount0Desired);
  token1.approve(await nonfungiblePositionMananger.getAddress(), amount1Desired);

  nonfungiblePositionMananger = nonfungiblePositionMananger.connect(contractOwner);
  await nonfungiblePositionMananger.mint(
    {
        token0: uniswap.token0,
        token1: uniswap.token1,
        fee: uniswap.fee,
        tickLower: BigInt(-58140),
        tickUpper: BigInt(-56640),
        amount0Desired,
        amount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: contractOwner.address,
        deadline: 1000 + Math.floor(Date.now() / 1000),
    }
  );

  return {
    operator,
    uniswap,
    owner: contractOwner,
  };
}

describe("DeltaNeutral - Basic Liftcycle", () => {
  let testSetup: TestSetup;

  beforeEach(async () => {
    testSetup = await setupTest();
  });

  it("swap 0 for 1 to mint", async () => {
    const { operator, uniswap } = testSetup;

    // open first vault
    const amount0 = ethers.parseEther("1");
    const amount1 = ethers.parseEther("0");

    const tickLower = -58680;
    const tickUpper = -56640;
    const slippage = JSBI.BigInt(50); // 0.5%

    await operator.injectFunds(amount0, amount1);

    const [quote, , ] = await operator.quotePool(
      tickLower,
      tickUpper,
      slippage
    );

    const mintEvent = await operator.swapAndMint(quote, tickLower, tickUpper);
    expect(mintEvent.tickLower).to.be.eq(tickLower);
    expect(mintEvent.tickUpper).to.be.eq(tickUpper);

    const position = await operator.getPosition();
    expect(mintEvent.amount0).to.be.eq(position.openPositionAmount0);
    expect(mintEvent.amount1).to.be.eq(position.openPositionAmount1);
  
    const ratioDeltaBefore = await operator.tokenAmountDelta();

    await operator.swap(
      await uniswap.pool.getAddress(),
      uniswap.token0,
      {
        zeroForOne: true,
        priceSqrtX96Limit: 1000000000000000000000n,
        amountOutMin: 0n,
        amountIn: ethers.parseEther("10000")
      }
    );
    
    // used token 0 to buy token 1, amount 0 should have increased while amount 1 should have dropped
    const ratioDeltaAfter = await operator.tokenAmountDelta();

    expect(ratioDeltaAfter[0]).to.be.greaterThan(ratioDeltaBefore[0]);
    expect(ratioDeltaAfter[1]).to.be.lessThan(ratioDeltaBefore[1]);
  });

  it("estimate range", async () => {
    const { operator, uniswap } = testSetup;

    const range = 0.001;
    const ticks = await operator.deriveTickRange(range);
    console.log(ticks, (await operator.priceSqrt()).toString());
  });
});
