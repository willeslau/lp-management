import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { deployUniswapFactory, UniswapPool } from "./uniswapV3Deployer";
import { deployContractWithDeployer } from "../scripts/util";
import { expect } from "chai";

interface TestSetup {
  caller: Signer;
  owner: Signer;
  uniswap: UniswapPool;
  mathContract: Contract,
}

async function setupTest(): Promise<TestSetup> {
  const [caller, owner] = await ethers.getSigners();

  // ==============================================
  // =========== setup uniswap related ============
  // ==============================================
  let uniswap;
  {
    const tokenA = await deployContractWithDeployer(
      caller,
      "TestToken",
      [
        "UNI",
        "UNI",
        await caller.getAddress(),
        ethers.parseEther("100000000000"),
      ],
      true
    );
    const tokenB = await deployContractWithDeployer(
      caller,
      "TestToken",
      [
        "ETH",
        "ETH",
        await caller.getAddress(),
        ethers.parseEther("100000000000"),
      ],
      true
    );
    const fee = 3000;
    const initialPriceSqrtQ96 = 4436738577262596212334852517n;
    uniswap = await deployUniswapFactory(
      owner,
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      fee,
      initialPriceSqrtQ96
    );
  }
  // ==============================================
  // =========== setup uniswap related ============
  // ==============================================

  const mathContract = await deployContractWithDeployer(
      caller,
      "RebalanceSwapMath",
      [],
      true
  );

  return {
    mathContract,
    uniswap,
    caller,
    owner,
  };
}

describe("RebalanceSwapMath", () => {
  let testSetup: TestSetup;

  beforeEach(async () => {
    testSetup = await setupTest();
  });

  it("zero for one - works", async () => {
    const { uniswap, mathContract } = testSetup;

    const tickLower = -58680;
    const tickUpper = -56640;

    const output = await mathContract.calculateSwapState(
      uniswap.pool,
      {
        zeroForOne: true,
        priceLimitSqrt: 4425628983865130671419166046n,
        priceLimit: 3120260389028180n,
      },
      tickLower,
      tickUpper,
      ethers.parseEther("1"),
      ethers.parseEther("0.001"),
    );
    expect(output[0]).to.be.eq(347009903476629996n);
    expect(output[1]).to.be.eq(1082761256418620n);
  });

  it("zero for one - no token 1", async () => {
    const { uniswap, mathContract } = testSetup;

    const tickLower = -58680;
    const tickUpper = -56640;

    const output = await mathContract.calculateSwapState(
      uniswap.pool,
      {
        zeroForOne: true,
        priceLimitSqrt: 4425628983865130671419166046n,
        priceLimit: 3120260389028180n,
        // no slippage check
        minOutPerIn: 0n
      },
      tickLower,
      tickUpper,
      ethers.parseEther("1"),
      ethers.parseEther("0"),
    );
    expect(output[0]).to.be.eq(505492629049560760n);
    expect(output[1]).to.be.eq(1577268627369059n);
  });

  it("one for zero - no token 0", async () => {
    const { uniswap, mathContract } = testSetup;

    const tickLower = -58680;
    const tickUpper = -56640;

    const output = await mathContract.calculateSwapState(
      uniswap.pool,
      {
        zeroForOne: false,
        priceLimitSqrt: 4447812676751443652480840308n,
        priceLimit: 3151619719009090n,
        // no slippage check
        minOutPerIn: 0n
      },
      tickLower,
      tickUpper,
      ethers.parseEther("0"),
      ethers.parseEther("1"),
    );
    expect(output[0]).to.be.eq(157698975528264028186n);
    expect(output[1]).to.be.eq(497007200942408836n);
  });

  it("one for zero - works", async () => {
    const { uniswap, mathContract } = testSetup;

    const tickLower = -58680;
    const tickUpper = -56640;

    const output = await mathContract.calculateSwapState(
      uniswap.pool,
      {
        zeroForOne: false,
        priceLimitSqrt: 4447812676751443652480840308n,
        priceLimit: 3151619719009090n,
        // no slippage check
        minOutPerIn: 0n
      },
      tickLower,
      tickUpper,
      ethers.parseEther("0.001"),
      ethers.parseEther("1"),
    );
    expect(output[0]).to.be.eq(157698472535464970595n);
    expect(output[1]).to.be.eq(497005615700384807n);
  });
});
