import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { deployUniswapFactory, UniswapPool } from "./uniswapV3Deployer";
import { deployContractWithDeployer, deployUpgradeableContract, loadContract } from "../scripts/util";
import { LPManagerTest } from "./LPManagerTest";
import { RushBuy } from "../scripts/RushBuy";
import { expect } from "chai";

const Q96 = 79228162514264337593543950336n;

interface TestSetup {
  rushBuy: RushBuy;
  owner: Signer;
  token0: Contract;
  token1: Contract;
  uniswap: UniswapPool;
}

async function setupTest(): Promise<TestSetup> {
  const [owner, initProvider] = await ethers.getSigners();

  const token0 = await deployContractWithDeployer(
    owner,
    "TestToken",
    [
      "UNI",
      "UNI",
      await owner.getAddress(),
      ethers.parseEther("100000000000"),
    ],
    true
  );
  const token1 = await deployContractWithDeployer(
    owner,
    "TestToken",
    [
      "ETH",
      "ETH",
      await owner.getAddress(),
      ethers.parseEther("100000000000"),
    ],
    true
  );
  const fee = 500;
  const initialPriceSqrtQ96 = 27169599998237907265358521n;
  const uniswap = await deployUniswapFactory(
    initProvider,
    await token0.getAddress(),
    await token1.getAddress(),
    fee,
    initialPriceSqrtQ96
  );

  const swapUtil = await deployContractWithDeployer(
    initProvider,
    "SwapUtil",
    [],
    true
  );

  const supportedTokenPairs = await deployContractWithDeployer(
    initProvider,
    "UniswapV3TokenPairs",
    [],
    true
  );

  await supportedTokenPairs.addTokenPair(
    await uniswap.pool.getAddress(),
    uniswap.token0,
    uniswap.token1,
    fee
  );

  const contract = await deployUpgradeableContract(
    owner,
    "RushBuy",
    [
      await swapUtil.getAddress(),
    ],
    true
  );

  const lpManagerTest = new LPManagerTest(
    await deployContractWithDeployer(
      initProvider,
      "UniswapV3LpManagerTest",
      [
        await supportedTokenPairs.getAddress(),
        await initProvider.getAddress(),
        await initProvider.getAddress(),
      ],
      true
    )
  );

  const mintParams = {
    tokenPairId: 1,
    amount0: 199999999999999999999999379n,
    amount1: 23519999999451196272n,
    tickLower: BigInt(-887250),
    tickUpper: BigInt(887250),
    slippage: 0,
  }
  await token0.transfer(initProvider.address, mintParams.amount0);
  await token1.transfer(initProvider.address, mintParams.amount1);

  await setupUniswapPoolPosition(lpManagerTest, uniswap, initProvider, mintParams);

  return {
    uniswap,
    rushBuy: await RushBuy.fromConfig(owner, await contract.getAddress()),
    owner,
    token0,
    token1
  };
}

interface MintNewPostionParams {
  amount0: bigint;
  amount1: bigint;
  tokenPairId: number;
  tickLower: bigint;
  tickUpper: bigint;
  slippage: number;
}

// simulate real world scenario where others have supplied liquidity
async function setupUniswapPoolPosition(
  lpManager: LPManagerTest,
  uniswap: UniswapPool,
  liquidityOwner: Signer,
  mintParams: MintNewPostionParams,
): Promise<void> {
  lpManager.useCaller(liquidityOwner);

  await lpManager.increaseAllowanceIfNeeded(uniswap.token0, mintParams.amount0);
  await lpManager.increaseAllowanceIfNeeded(uniswap.token1, mintParams.amount1);

  const params = lpManager.createMintParams(
    mintParams.tickLower,
    mintParams.tickUpper,
    mintParams.amount0,
    mintParams.amount1,
    mintParams.slippage
  );
  const pos = await lpManager.mintNewPosition(mintParams.tokenPairId, params);
}

describe("RushBuy", () => {
  it("rush buy 1 for 0 - works", async () => {
    const testSetup = await setupTest();

    const { rushBuy, token0, token1, uniswap } = testSetup;

    const amount = ethers.parseEther("1");
    await token1.transfer(rushBuy.address, amount);

    const maxSlippage = 0.6;
    const lowerRange = 0.6;
    const upperRange = 1.5;

    const buyParams = await rushBuy.createBuyParams(
      await uniswap.pool.getAddress(),
      await token0.getAddress(),
      await token1.getAddress(),
      await token0.decimals(),
      await token1.decimals(),
      false,
      maxSlippage,
      lowerRange,
      upperRange,
    );

    const params = await rushBuy.calculateSwapState(buyParams);

    expect(params.zeroForOne).to.be.eq(false);
    expect(params.rX96).to.be.eq(549417705449063204820612140437164839n);
    expect(params.tickLower).to.be.eq(-164670);
    expect(params.tickUpper).to.be.eq(-155510);
    expect(params.priceRatioUpperX96).to.be.eq(33280640147896965742795058n);
    expect(params.priceRatioLowerX96).to.be.eq(21052066986795418405691012n);

    const r = Q96 * params.amountOut / (amount - params.amountIn);
    const base = BigInt(10000000000000000000n);
    const diff = base * (r - params.rX96) / r;
    const diffNum = Number(diff) / Number(base);
    expect(diffNum).to.be.lessThan(0.001);

    await rushBuy.buy(buyParams);
    await rushBuy.closePosition();

    const buyParams2 = await rushBuy.createBuyParams(
      await uniswap.pool.getAddress(),
      await token0.getAddress(),
      await token1.getAddress(),
      await token0.decimals(),
      await token1.decimals(),
      true,
      maxSlippage,
      lowerRange,
      upperRange,
    );
    await rushBuy.buy(buyParams2);

  });

  // it("rush buy 0 for 1 - works", async () => {
  //   const { lpManager, balancer } = testSetup;

  //   await lpManager.useCaller(balancer);

  //   await lpManager.rebalance({
  //     vaultId: 0,
  //     swap: {
  //       swapper: Swapper.UniswapPool,
  //       zeroForOne: true,
  //       priceSqrtX96Limit: 4303636419944718166428483584n,
  //       amountOutMin: ethers.parseEther("1000000"), // just a big number, no slippage
  //       amountIn: ethers.parseEther("0.5049756225615896"),
  //     },
  //     mint: {
  //       tickLower: -58680,
  //       tickUpper: -56640,
  //       amount0Min: 0n,
  //       amount1Min: 0n
  //     },
  //   });

  //   const vaultDetails = await lpManager.listVaults([0]);
  //   console.log(vaultDetails);
  // });
  //     tokenPairId,
  //     // local testing, no need slippage protection
  //     sqrtPriceLimitX96: 4880412434988856429110099968n,
  //     maxMintSlippageRate: testSetup.lpManager.toOnChainRate(0.03),
  //     tickLower: -58680n,
  //     tickUpper: -56640n,
  //     R_Q96: 252704211256043437387939840n,
  //     amount0: ethers.parseEther("0"),
  //     amount1: ethers.parseEther("0.01"),
  //     searchRange: {
  //       swapInLow: ethers.parseEther("0.004956984791606578"),
  //       swapInHigh: ethers.parseEther("0.004971855745981397"),
  //       searchLoopNum: 5,
  //     },
  //   };
  //   const initialPosition = await setupInitialPosition(
  //     testSetup.lpManager,
  //     testSetup.liquidityOwner,
  //     testSetup.balancer,
  //     initialRebalanceParams
  //   );

  //   const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
  //   const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
  //   const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
  //   const token0InitialBalance = await token0.balanceOf(
  //     await lpManager.innerContract.getAddress()
  //   );
  //   const token1InitialBalance = await token1.balanceOf(
  //     await lpManager.innerContract.getAddress()
  //   );

  //   await lpManager.useCaller(balancer);

  //   const params = {
  //     amount0Min: BigInt(0),
  //     amount1Min: BigInt(0),
  //     compoundFee: true,
  //   };
  //   const positionChange = await lpManager.rebalanceClosePosition(
  //     initialPosition.positionKey,
  //     params
  //   );

  //   await checkEndReserve(lpManager, tokenPairId);
  //   expect(positionChange.change).to.eq(PositionChange.Closed);

  //   await expect(
  //     lpManager.getPosition(initialPosition.positionKey)
  //   ).to.revertedWithCustomError(lpManager.innerContract, "InvalidPositionKey");

  //   const token0AfterBalance = await token0.balanceOf(
  //     await lpManager.innerContract.getAddress()
  //   );
  //   const token1AfterBalance = await token1.balanceOf(
  //     await lpManager.innerContract.getAddress()
  //   );
  //   expect(token0InitialBalance + positionChange.amount0).to.be.eq(
  //     token0AfterBalance
  //   );
  //   expect(token1InitialBalance + positionChange.amount1).to.be.eq(
  //     token1AfterBalance
  //   );
  // });

  // it("rebalance 1 for 0 - should increase liquidity when position exists", async () => {
  //   const { lpManager, balancer, liquidityOwner } = testSetup;
  //   const amount = ethers.parseEther("0.01");

  //   await lpManager.useCaller(liquidityOwner);
  //   await lpManager.injectPricinple(tokenPairId, ethers.parseEther('0'), amount);
  //   await lpManager.useCaller(balancer);

  //   const rebalanceParams = {
  //     tokenPairId,
  //     sqrtPriceLimitX96: 4880412434988856429110099968n,
  //     maxMintSlippageRate: lpManager.toOnChainRate(1), // Changed from 0.03 to 1 to allow higher slippage
  //     tickLower: -58680n,
  //     tickUpper: -56640n,
  //     R_Q96: 252704211256043437387939840n,
  //     amount0: ethers.parseEther("0"),
  //     amount1: amount,
  //     searchRange: {
  //       swapInLow: ethers.parseEther("0.004956984791606578"),
  //       swapInHigh: ethers.parseEther("0.004971855745981397"),
  //       searchLoopNum: 5,
  //     },
  //   };

  //   await lpManager.useCaller(balancer);
  //   const initialPositionChange = await lpManager.rebalance1For0(rebalanceParams);
  //   await checkEndReserve(lpManager, tokenPairId);
  //   const initialPosition = await lpManager.getPosition(initialPositionChange.positionKey);
  //   const initialLiquidity = initialPosition.liquidity;

  //   // Rebalance again with same tick range to trigger increaseLiquidity
  //   await lpManager.useCaller(liquidityOwner);
  //   await lpManager.injectPricinple(tokenPairId, ethers.parseEther('0'), amount);
  //   await lpManager.useCaller(balancer);

  //   const positionChange = await lpManager.rebalance1For0(rebalanceParams);
  //   await checkEndReserve(lpManager, tokenPairId);

  //   expect(positionChange.change).to.eq(PositionChange.Increase);
  //   expect(positionChange.positionKey).to.eq(initialPositionChange.positionKey);

  //   const updatedPosition = await lpManager.getPosition(positionChange.positionKey);
  //   expect(updatedPosition.liquidity).to.be.gt(initialLiquidity);
  // });

  // it("rebalance 0 for 1 - should increase liquidity when position exists", async () => {
  //   const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
  //   const amount = ethers.parseEther("1");

  //   await lpManager.useCaller(liquidityOwner);
  //   await lpManager.injectPricinple(tokenPairId, amount, ethers.parseEther("0"));
  //   await lpManager.useCaller(balancer);

  //   const rebalanceParams = {
  //     tokenPairId,
  //     sqrtPriceLimitX96: 4303636419944718166428483584n,
  //     maxMintSlippageRate: lpManager.toOnChainRate(1), // Changed from 0.03 to 1 to allow higher slippage
  //     tickLower: -58680n,
  //     tickUpper: -56640n,
  //     R_Q96: 252704211256043437387939840n,
  //     amount0: amount,
  //     amount1: ethers.parseEther("0"),
  //     searchRange: {
  //       swapInLow: ethers.parseEther("0.5042192936211579"),
  //       swapInHigh: ethers.parseEther("0.5057319515020213"),
  //       searchLoopNum: 5,
  //     },
  //   };

  //   await lpManager.useCaller(liquidityOwner);
  //   await lpManager.injectPricinple(tokenPairId, amount, ethers.parseEther("0"));

  //   await lpManager.useCaller(balancer);
  //   const initialPositionChange = await lpManager.rebalance0For1(rebalanceParams);
  //   await checkEndReserve(lpManager, tokenPairId);

  //   const initialPosition = await lpManager.getPosition(initialPositionChange.positionKey);
  //   const initialLiquidity = initialPosition.liquidity;

  //   const positionChange = await lpManager.rebalance0For1(rebalanceParams);
  //   await checkEndReserve(lpManager, tokenPairId);

  //   expect(positionChange.change).to.eq(PositionChange.Increase);
  //   expect(positionChange.positionKey).to.eq(initialPositionChange.positionKey);

  //   const updatedPosition = await lpManager.getPosition(positionChange.positionKey);
  //   expect(updatedPosition.liquidity).to.be.gt(initialLiquidity);
  // });
});
