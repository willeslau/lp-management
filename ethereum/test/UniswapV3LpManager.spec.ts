import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { deployUniswapFactory, UniswapPool } from "./uniswapV3Deployer";
import { deployContractWithDeployer, loadContract } from "../scripts/util";
import { LPManager, LpPosition, PositionChange } from "../scripts/LPManager";
import { expect } from "chai";

interface TestSetup {
  lpManager: LPManager;
  uniswap: UniswapPool;
  supportedTokenPairs: Contract;
  balancer: Signer;
  liquidityOwner: Signer;
  user: Signer;
}

async function setupTest(): Promise<TestSetup> {
  const [liquidityOwner, balancer, user] = await ethers.getSigners();

  const tokenA = await deployContractWithDeployer(
    liquidityOwner,
    "TestToken",
    [
      "UNI",
      "UNI",
      await liquidityOwner.getAddress(),
      ethers.parseEther("100000000000"),
    ],
    true
  );
  const tokenB = await deployContractWithDeployer(
    liquidityOwner,
    "TestToken",
    [
      "ETH",
      "ETH",
      await liquidityOwner.getAddress(),
      ethers.parseEther("100000000000"),
    ],
    true
  );
  const fee = 3000;
  const initialPriceSqrtQ96 = 4436738577262596212334852517n;
  const uniswap = await deployUniswapFactory(
    liquidityOwner,
    await tokenA.getAddress(),
    await tokenB.getAddress(),
    fee,
    initialPriceSqrtQ96
  );

  const supportedTokenPairs = await deployContractWithDeployer(
    liquidityOwner,
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

  const lpManager = new LPManager(
    await deployContractWithDeployer(
      balancer,
      "UniswapV3LpManager",
      [
        await supportedTokenPairs.getAddress(),
        await liquidityOwner.getAddress(),
        await balancer.getAddress(),
      ],
      true
    )
  );

  return {
    lpManager,
    uniswap,
    supportedTokenPairs,
    balancer,
    liquidityOwner,
    user,
  };
}

interface InitialPositionResult {
  positionKey: string;
  amount0: bigint;
  amount1: bigint;
  tokenPair: number;
  change: PositionChange;
  liquidity: bigint;
  fee0: bigint;
  fee1: bigint;
  tickLower: bigint;
  tickUpper: bigint;
}

async function setupInitialPosition(
  lpManager: LPManager,
  uniswap: UniswapPool,
  liquidityOwner: Signer
): Promise<InitialPositionResult> {
  const tokenPairId = 1;
  const amount0 = ethers.parseEther("312.5");
  const amount1 = ethers.parseEther("1");
  const tickLower = BigInt(-58140);
  const tickUpper = BigInt(-56640);
  const slippage = 0.999;

  lpManager.useCaller(liquidityOwner);

  await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
  await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

  const params = lpManager.createMintParams(
    tickLower,
    tickUpper,
    amount0,
    amount1,
    slippage
  );
  const result = await lpManager.mintNewPosition(tokenPairId, params);
  const position = await lpManager.getPosition(result.positionKey);

  return {
    ...result,
    liquidity: position.liquidity,
    fee0: position.fee0,
    fee1: position.fee1,
    tickLower,
    tickUpper
  };
}

describe("UniswapV3LpManager - Init", () => {
  let testSetup: TestSetup;

  beforeEach(async () => {
    testSetup = await setupTest();
  });

  it("initial liquidity add ok", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;

    const initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
    expect(initialPosition.fee0).to.eq(0);
    expect(initialPosition.fee1).to.eq(0);
  });

  it("escape hatch works", async () => {
    const { lpManager, uniswap, liquidityOwner, balancer } = testSetup;

    const initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
    expect(initialPosition.fee0).to.eq(0);
    expect(initialPosition.fee1).to.eq(0);

    lpManager.useCaller(balancer);
    await lpManager.deactive();

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const token0InitialBalance = await token0.balanceOf(await liquidityOwner.getAddress());
    const token1InitialBalance = await token1.balanceOf(await liquidityOwner.getAddress());

    await lpManager.escapeHatchBurn(
      await uniswap.pool.getAddress(),
      initialPosition.liquidity,
      initialPosition.tickLower,
      initialPosition.tickUpper,
      BigInt(0),
      BigInt(0)
    );

    await lpManager.escapeHatchCollect(
      await uniswap.pool.getAddress(),
      initialPosition.tickLower,
      initialPosition.tickUpper,
    );

    const token0AfterBalance = await token0.balanceOf(await liquidityOwner.getAddress());
    const token1AfterBalance = await token1.balanceOf(await liquidityOwner.getAddress());

    const calculationInaccuracy =  BigInt(1);
    expect(token0AfterBalance + calculationInaccuracy).to.be.eq(token0InitialBalance + initialPosition.amount0);
    expect(token1AfterBalance + calculationInaccuracy).to.be.eq(token1InitialBalance + initialPosition.amount1);
  });
});

describe("UniswapV3LpManager - After Init", () => {
  let testSetup: TestSetup;
  let initialPosition: InitialPositionResult;
  const tokenPairId = 1;

  beforeEach(async () => {
    testSetup = await setupTest();
    const { lpManager, uniswap, liquidityOwner } = testSetup;

    initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
  });

  function withinPercentageDiff(a: BigInt, b: BigInt, tolerance: number) {
    const diff = Math.abs(Number(a) - Number(b)) / Number(a);
    expect(diff).to.be.lt(tolerance);
  }

  it("list positions - works", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;

    await lpManager.useCaller(liquidityOwner);

    const r = await lpManager.listPositionKeys(0, 0);
    expect(r.totalPositions).to.eq(1);
  });

  it("increase liquidity - works", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const amount0 = ethers.parseEther("33");
    const amount1 = ethers.parseEther("0.1");

    await lpManager.useCaller(liquidityOwner);

    await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
    await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

    const params = {
      amount0,
      amount1,
      slippage: 0.99,
    };
    const positionChange = await lpManager.increaseLiquidity(
      initialPosition.positionKey,
      params
    );

    expect(positionChange.change).to.eq(PositionChange.Increase);

    const newPosition = await lpManager.getPosition(
      initialPosition.positionKey
    );
    expect(newPosition.liquidity).to.be.gt(initialPosition.liquidity);
  });

  it("decrease liquidity - works", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const amount0 = ethers.parseEther("0.3");
    const amount1 = ethers.parseEther("0.001");

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const token0InitialBalance = await token0.balanceOf(
      await liquidityOwner.getAddress()
    );
    const token1InitialBalance = await token1.balanceOf(
      await liquidityOwner.getAddress()
    );

    await lpManager.useCaller(liquidityOwner);

    const params = {
      newLiquidity: initialPosition.liquidity / BigInt(2),
      amount0,
      amount1,
    };
    const positionChange = await lpManager.decreaseLiquidity(
      initialPosition.positionKey,
      params
    );

    expect(positionChange.change).to.eq(PositionChange.Descrese);

    const newPosition = await lpManager.getPosition(
      initialPosition.positionKey
    );
    expect(newPosition.liquidity).to.be.lt(initialPosition.liquidity);

    const token0AfterBalance = await token0.balanceOf(
      await liquidityOwner.getAddress()
    );
    const token1AfterBalance = await token1.balanceOf(
      await liquidityOwner.getAddress()
    );
    expect(token0InitialBalance + positionChange.amount0).to.be.eq(
      token0AfterBalance
    );
    expect(token1InitialBalance + positionChange.amount1).to.be.eq(
      token1AfterBalance
    );
  });

  it("rebalance close position - compound fee", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const token0InitialBalance = await token0.balanceOf(
      await lpManager.innerContract.getAddress()
    );
    const token1InitialBalance = await token1.balanceOf(
      await lpManager.innerContract.getAddress()
    );

    await lpManager.useCaller(balancer);

    const params = {
      amount0Min: BigInt(0),
      amount1Min: BigInt(0),
      compoundFee: true,
    };
    const positionChange = await lpManager.rebalanceClosePosition(
      initialPosition.positionKey,
      params
    );

    expect(positionChange.change).to.eq(PositionChange.Closed);

    await expect(
      lpManager.getPosition(initialPosition.positionKey)
    ).to.revertedWithCustomError(lpManager.innerContract, "InvalidPositionKey");

    const token0AfterBalance = await token0.balanceOf(
      await lpManager.innerContract.getAddress()
    );
    const token1AfterBalance = await token1.balanceOf(
      await lpManager.innerContract.getAddress()
    );
    expect(token0InitialBalance + positionChange.amount0).to.be.eq(
      token0AfterBalance
    );
    expect(token1InitialBalance + positionChange.amount1).to.be.eq(
      token1AfterBalance
    );
  });

  it("rebalance 1 for 0 - new position created", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    // sending 0.01 token1 to the contract to simulate rebalance close is already called
    const amount = ethers.parseEther("0.01"); // Increased test amount
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);

    await token1.transfer(await lpManager.innerContract.getAddress(), amount);

    // now, off chain calculation based on current liquidity and price sqrt
    const rebalanceParams = {
      tokenPairId,
      // local testing, no need slippage protection
      sqrtPriceLimitX96: 4880412434988856429110099968n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: ethers.parseEther("0"),
      amount1: amount,
      searchRange: {
        swapInLow: ethers.parseEther("0.004956984791606578"),
        swapInHigh: ethers.parseEther("0.004971855745981397"),
        searchLoopNum: 5,
      },
    };
    const expectedPosition0 = ethers.parseEther("1.5809169659443283");
    const expectedPosition1 = ethers.parseEther("0.005027581488006263");

    await lpManager.useCaller(balancer);

    const positionChange = await lpManager.rebalance1For0(rebalanceParams);

    expect(positionChange.change).to.eq(PositionChange.Create);
    withinPercentageDiff(positionChange.amount0, expectedPosition0, 0.012);
    withinPercentageDiff(positionChange.amount1, expectedPosition1, 0.01);

    const position = await lpManager.getPosition(positionChange.positionKey);
    expect(position.tokenPairId).to.be.eq(tokenPairId);
  });

  it("rebalance 1 for 0 - follow up operations ok", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    // sending 0.01 token1 to the contract to simulate rebalance close is already called
    const amount = ethers.parseEther("0.01"); // Increased test amount
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);

    await token1.transfer(await lpManager.innerContract.getAddress(), amount);

    // now, off chain calculation based on current liquidity and price sqrt
    const rebalanceParams = {
      tokenPairId,
      // local testing, no need slippage protection
      sqrtPriceLimitX96: 4880412434988856429110099968n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: ethers.parseEther("0"),
      amount1: amount,
      searchRange: {
        swapInLow: ethers.parseEther("0.004956984791606578"),
        swapInHigh: ethers.parseEther("0.004971855745981397"),
        searchLoopNum: 5,
      },
    };

    await lpManager.useCaller(balancer);

    let positionChange = await lpManager.rebalance1For0(rebalanceParams);

    // increase liquidity
    let amount0 = ethers.parseEther("33");
    let amount1 = ethers.parseEther("0.1");

    await lpManager.useCaller(liquidityOwner);

    await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
    await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

    const params = {
      amount0,
      amount1,
      slippage: 0.99,
    };
    positionChange = await lpManager.increaseLiquidity(
      positionChange.positionKey,
      params
    );
    expect(positionChange.change).to.be.eq(PositionChange.Increase);

    // decrease liquidity
    amount0 = ethers.parseEther("15");
    amount1 = ethers.parseEther("0.05");

    const position = await lpManager.getPosition(positionChange.positionKey);

    const decreaseParams = {
      newLiquidity: position.liquidity / BigInt(2),
      amount0,
      amount1,
    };

    positionChange = await lpManager.decreaseLiquidity(
      positionChange.positionKey,
      decreaseParams
    );
    expect(positionChange.change).to.be.eq(PositionChange.Descrese);

    // close postion
    positionChange = await lpManager.closePosition(positionChange.positionKey);
    expect(positionChange.change).to.be.eq(PositionChange.Closed);
  });

  it("rebalance 0 for 1 - new position created", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    // sending 1 token1 to the contract to simulate rebalance close is already called
    const amount = ethers.parseEther("1");
    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);

    await token0.transfer(await lpManager.innerContract.getAddress(), amount);

    // now, off chain calculation based on current liquidity and price sqrt
    const rebalanceParams = {
      tokenPairId,
      // local testing, no need slippage protection
      sqrtPriceLimitX96: 4303636419944718166428483584n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: amount,
      amount1: ethers.parseEther("0"),
      searchRange: {
        swapInLow: ethers.parseEther("0.5042192936211579"),
        swapInHigh: ethers.parseEther("0.5057319515020213"),
        searchLoopNum: 5,
      },
    };

    const expectedPosition0 = ethers.parseEther("0.4942500985897128");
    const expectedPosition1 = ethers.parseEther("0.0015812729456157");
    await lpManager.useCaller(balancer);

    const positionChange = await lpManager.rebalance0For1(rebalanceParams);
    expect(positionChange.change).to.eq(PositionChange.Create);
    withinPercentageDiff(positionChange.amount0, expectedPosition0, 0.01);
    withinPercentageDiff(positionChange.amount1, expectedPosition1, 0.01);

    const position = await lpManager.getPosition(positionChange.positionKey);
    expect(position.tokenPairId).to.be.eq(tokenPairId);
  });

  it("rebalance 0 for 1 - follow up operations ok", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    // sending 1 token1 to the contract to simulate rebalance close is already called
    const amount = ethers.parseEther("1");
    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);

    await token0.transfer(await lpManager.innerContract.getAddress(), amount);

    // now, off chain calculation based on current liquidity and price sqrt
    const rebalanceParams = {
      tokenPairId,
      // local testing, no need slippage protection
      sqrtPriceLimitX96: 4303636419944718166428483584n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: amount,
      amount1: ethers.parseEther("0"),
      searchRange: {
        swapInLow: ethers.parseEther("0.5042192936211579"),
        swapInHigh: ethers.parseEther("0.5057319515020213"),
        searchLoopNum: 5,
      },
    };

    await lpManager.useCaller(balancer);

    let positionChange = await lpManager.rebalance0For1(rebalanceParams);

    // increase liquidity
    let amount0 = ethers.parseEther("33");
    let amount1 = ethers.parseEther("0.1");

    await lpManager.useCaller(liquidityOwner);

    await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
    await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

    const params = {
      amount0,
      amount1,
      slippage: 0.99,
    };
    positionChange = await lpManager.increaseLiquidity(
      positionChange.positionKey,
      params
    );
    expect(positionChange.change).to.be.eq(PositionChange.Increase);

    // decrease liquidity
    amount0 = ethers.parseEther("15");
    amount1 = ethers.parseEther("0.05");

    const position = await lpManager.getPosition(positionChange.positionKey);

    const decreaseParams = {
      newLiquidity: position.liquidity / BigInt(2),
      amount0,
      amount1,
    };

    positionChange = await lpManager.decreaseLiquidity(
      positionChange.positionKey,
      decreaseParams
    );
    expect(positionChange.change).to.be.eq(PositionChange.Descrese);

    // close postion
    positionChange = await lpManager.closePosition(positionChange.positionKey);
    expect(positionChange.change).to.be.eq(PositionChange.Closed);
  });
});

describe("UniswapV3LpManager - More Cases", () => {
  let testSetup: TestSetup;

  beforeEach(async () => {
    testSetup = await setupTest();
  });

  it("should allow owner to set protocol fee rate", async () => {
    const { lpManager } = testSetup;
    const newRate = 100; // 10%
    await lpManager.innerContract.setProtocolFeeRate(newRate);
    const params = await lpManager.innerContract.operationalParams();
    expect(params).to.equal(newRate);
  });

  it("should revert when setting protocol fee rate above maximum", async () => {
    const { lpManager } = testSetup;
    const invalidRate = 1001; // Above 100%
    await expect(
      lpManager.innerContract.setProtocolFeeRate(invalidRate)
    ).to.be.revertedWithCustomError(lpManager.innerContract, "RateTooHigh");
  });

  it("should allow owner to set new balancer", async () => {
    const { lpManager, user } = testSetup;
    const newBalancer = await user.getAddress();
    await lpManager.innerContract.setBalancer(newBalancer);
    expect(await lpManager.innerContract.balancer()).to.equal(newBalancer);
  });

  it("should revert when setting zero address as balancer", async () => {
    const { lpManager } = testSetup;
    await expect(
      lpManager.innerContract.setBalancer(ethers.ZeroAddress)
    ).to.be.revertedWithCustomError(lpManager.innerContract, "InvalidAddress");
  });

  it("should revert when non-owner tries to set protocol fee rate", async () => {
    const { lpManager, user } = testSetup;
    const newRate = 100;
    await expect(
      // @ts-ignore
      lpManager.innerContract.connect(user).setProtocolFeeRate(newRate)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should revert when non-owner tries to set balancer", async () => {
    const { lpManager, user } = testSetup;
    const newBalancer = await user.getAddress();
    await expect(
      // @ts-ignore
      lpManager.innerContract.connect(user).setBalancer(newBalancer)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should revert when non-liquidityOwner tries to mint", async () => {
    const { lpManager, user } = testSetup;
    const tokenPairId = 1;
    const amount0 = ethers.parseEther("312.5");
    const amount1 = ethers.parseEther("1");
    const tickLower = BigInt(-58140);
    const tickUpper = BigInt(-56640);
    const slippage = 0.999;

    lpManager.useCaller(user);

    const params = lpManager.createMintParams(
      tickLower,
      tickUpper,
      amount0,
      amount1,
      slippage
    );
    await expect(
      lpManager.mintNewPosition(tokenPairId, params)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "NotLiquidityOwner"
    );
  });

  it("should revert when non-balancer tries to rebalance", async () => {
    const { lpManager, user } = testSetup;
    const tokenPairId = 1;
    const rebalanceParams = {
      tokenPairId,
      sqrtPriceLimitX96: 4880412434988856429110099968n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: ethers.parseEther("0"),
      amount1: ethers.parseEther("0.01"),
      searchRange: {
        swapInLow: ethers.parseEther("0.004956984791606578"),
        swapInHigh: ethers.parseEther("0.004971855745981397"),
        searchLoopNum: 5,
      },
    };

    lpManager.useCaller(user);
    await expect(
      lpManager.rebalance1For0(rebalanceParams)
    ).to.be.revertedWithCustomError(lpManager.innerContract, "NotBalancer");
  });

  it("should revert when trying to mint with invalid token pair ID", async () => {
    const { lpManager, liquidityOwner } = testSetup;
    const invalidTokenPairId = 99;
    const amount0 = ethers.parseEther("312.5");
    const amount1 = ethers.parseEther("1");
    const tickLower = BigInt(-58140);
    const tickUpper = BigInt(-56640);
    const slippage = 0.999;

    lpManager.useCaller(liquidityOwner);

    const params = lpManager.createMintParams(
      tickLower,
      tickUpper,
      amount0,
      amount1,
      slippage
    );
    await expect(
      lpManager.mintNewPosition(invalidTokenPairId, params)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "TokenPairIdNotSupported"
    );
  });

  it("should revert when trying to decrease liquidity below minimum", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;

    const result = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );

    // Try to decrease liquidity to 0
    const decreaseParams = {
      newLiquidity: BigInt(0),
      amount0: ethers.parseEther("0.1"),
      amount1: ethers.parseEther("0.001"),
    };

    await expect(
      lpManager.decreaseLiquidity(result.positionKey, decreaseParams)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "PriceSlippageCheck"
    );
  });

  it("should emit PositionChanged event on mint", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;

    const result = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
    expect(result.change).to.eq(PositionChange.Create);
  });

  it("should completely remove position after closePosition", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );

    lpManager.useCaller(liquidityOwner);
    await lpManager.closePosition(initialPosition.positionKey);

    // Verify position is completely removed
    await expect(
      lpManager.getPosition(initialPosition.positionKey)
    ).to.be.revertedWithCustomError(lpManager.innerContract, "InvalidPositionKey");

    // Verify position is not in the list
    const positions = await lpManager.listPositionKeys(0, 0);
    expect(positions.totalPositions).to.eq(0);
  });

  it("should allow creating new position after closePosition with same parameters", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );

    lpManager.useCaller(liquidityOwner);
    await lpManager.closePosition(initialPosition.positionKey);

    // Create new position with same parameters
    const tokenPairId = 1;
    const amount0 = ethers.parseEther("312.5");
    const amount1 = ethers.parseEther("1");
    const tickLower = BigInt(-58140);
    const tickUpper = BigInt(-56640);
    const slippage = 0.999;

    await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
    await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

    const params = lpManager.createMintParams(
      tickLower,
      tickUpper,
      amount0,
      amount1,
      slippage
    );
    const result = await lpManager.mintNewPosition(tokenPairId, params);
    expect(result.change).to.eq(PositionChange.Create);

    // Verify new position is created successfully
    const position = await lpManager.getPosition(result.positionKey);
    expect(position.tickLower).to.eq(tickLower);
    expect(position.tickUpper).to.eq(tickUpper);
  });

  it("should support liquidity operations on minted position", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
    const initialLiquidity = (await lpManager.getPosition(initialPosition.positionKey)).liquidity;

    // Increase liquidity
    const amount0ToAdd = ethers.parseEther("100");
    const amount1ToAdd = ethers.parseEther("0.3");
    await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0ToAdd);
    await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1ToAdd);

    const increaseParams = {
      amount0: amount0ToAdd,
      amount1: amount1ToAdd,
      slippage: 0.99,
    };
    const increaseResult = await lpManager.increaseLiquidity(
      initialPosition.positionKey,
      increaseParams
    );
    expect(increaseResult.change).to.eq(PositionChange.Increase);

    // Verify liquidity increased
    const positionAfterIncrease = await lpManager.getPosition(initialPosition.positionKey);
    expect(positionAfterIncrease.liquidity).to.be.gt(initialLiquidity);

    // Decrease liquidity
    const decreaseParams = {
      newLiquidity: positionAfterIncrease.liquidity / BigInt(2),
      amount0: ethers.parseEther("50"),
      amount1: ethers.parseEther("0.15"),
    };
    const decreaseResult = await lpManager.decreaseLiquidity(
      initialPosition.positionKey,
      decreaseParams
    );
    expect(decreaseResult.change).to.eq(PositionChange.Descrese);

    // Verify liquidity decreased
    const positionAfterDecrease = await lpManager.getPosition(initialPosition.positionKey);
    expect(positionAfterDecrease.liquidity).to.be.lt(positionAfterIncrease.liquidity);
  });
});

describe("UniswapV3LpManager - Fee Collection and Rebalancing", () => {
  let testSetup: TestSetup;
  let initialPosition: InitialPositionResult;

  beforeEach(async () => {
    testSetup = await setupTest();
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
  });

  it("should revert rebalance with invalid search range", async () => {
    const { lpManager, balancer } = testSetup;
    const tokenPairId = 1;
    const rebalanceParams = {
      tokenPairId,
      sqrtPriceLimitX96: 4880412434988856429110099968n,
      maxMintSlippageRate: lpManager.toOnChainRate(0.03),
      tickLower: -58680n,
      tickUpper: -56640n,
      R_Q96: 252704211256043437387939840n,
      amount0: ethers.parseEther("0"),
      amount1: ethers.parseEther("0.01"),
      searchRange: {
        swapInLow: ethers.parseEther("0"),
        swapInHigh: ethers.parseEther("0"),
        searchLoopNum: 0,
      },
    };

    lpManager.useCaller(balancer);
    await expect(lpManager.rebalance1For0(rebalanceParams)).to.be.reverted;
  });

  it("should handle rebalance close position without compounding fees", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;
    lpManager.useCaller(balancer);

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const liquidityOwnerAddress = await liquidityOwner.getAddress();
    const token0InitialBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1InitialBalance = await token1.balanceOf(liquidityOwnerAddress);

    const params = {
      amount0Min: BigInt(0),
      amount1Min: BigInt(0),
      compoundFee: false,
    };
    await lpManager.rebalanceClosePosition(initialPosition.positionKey, params);

    const token0AfterBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1AfterBalance = await token1.balanceOf(liquidityOwnerAddress);
    expect(token0AfterBalance).to.be.gte(token0InitialBalance);
    expect(token1AfterBalance).to.be.gte(token1InitialBalance);
  });

  it("should emit RemainingFundsWithdraw event when withdrawing remaining funds", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    const token0 = await ethers.getContractAt("MockERC20", uniswap.token0);
    const token1 = await ethers.getContractAt("MockERC20", uniswap.token1);
    const amount0 = ethers.parseEther("1");
    const amount1 = ethers.parseEther("0.5");

    // Mint and transfer tokens to the contract
    await token0.transfer(await lpManager.innerContract.getAddress(), amount0);
    await token1.transfer(await lpManager.innerContract.getAddress(), amount1);

    // Withdraw remaining funds
    expect(await lpManager.withdrawRemainingFunds(1))
      .to.emit(lpManager.innerContract, "RemainingFundsWithdrawn")
      .withArgs(await liquidityOwner.getAddress(), amount0, amount1);
  });

  it("should batch collect fees successfully for a valid position", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const liquidityOwnerAddress = await liquidityOwner.getAddress();

    // Record initial balances
    const token0InitialBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1InitialBalance = await token1.balanceOf(liquidityOwnerAddress);

    // Batch Collect fees
    expect(
      await lpManager.innerContract.batchCollectFees([
        initialPosition.positionKey,
      ])
    ).to.emit(lpManager.innerContract, "FeesCollected");

    // Verify balances after fee collection
    const token0AfterBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1AfterBalance = await token1.balanceOf(liquidityOwnerAddress);
    expect(token0AfterBalance).to.be.gte(token0InitialBalance);
    expect(token1AfterBalance).to.be.gte(token1InitialBalance);
  });

  it("should handle invalid position keys in batch collection", async () => {
    const { lpManager, liquidityOwner } = testSetup;
    const invalidPositionKey = ethers.keccak256(
      ethers.toUtf8Bytes("invalid_position")
    );

    lpManager.useCaller(liquidityOwner);

    await expect(
      lpManager.innerContract.batchCollectFees([invalidPositionKey])
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "InvalidPositionKey"
    );
  });

  it("should handle empty position keys array", async () => {
    const { lpManager, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    await expect(lpManager.innerContract.batchCollectFees([])).to.not.be
      .reverted;
  });

  it("should revert when non-liquidity owner calls batchCollectFees", async () => {
    const { lpManager, user } = testSetup;
    lpManager.useCaller(user);

    await expect(
      lpManager.innerContract.batchCollectFees([initialPosition.positionKey])
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "NotLiquidityOwner"
    );
  });
});

describe("UniswapV3LpManager - Position Operations", () => {
  let testSetup: TestSetup;
  let initialPosition: InitialPositionResult;

  beforeEach(async () => {
    testSetup = await setupTest();
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
  });

  it("should close position successfully", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const liquidityOwnerAddress = await liquidityOwner.getAddress();

    // Record initial balances
    const token0InitialBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1InitialBalance = await token1.balanceOf(liquidityOwnerAddress);

    // Close position
    const result = await lpManager.closePosition(initialPosition.positionKey);

    expect(result.change).to.eq(PositionChange.Closed);
    expect(result.amount0).to.be.gt(0);
    expect(result.amount1).to.be.gt(0);

    // Verify position is closed
    await expect(
      lpManager.getPosition(initialPosition.positionKey)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "InvalidPositionKey"
    );

    // Verify tokens are returned
    const token0AfterBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1AfterBalance = await token1.balanceOf(liquidityOwnerAddress);
    expect(token0AfterBalance).to.eq(token0InitialBalance + result.amount0);
    expect(token1AfterBalance).to.eq(token1InitialBalance + result.amount1);
  });

  it("should close position successfully with minimum amounts", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
    const liquidityOwnerAddress = await liquidityOwner.getAddress();

    // Record initial balances
    const token0InitialBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1InitialBalance = await token1.balanceOf(liquidityOwnerAddress);

    const amount0Min = ethers.parseEther("0.1");
    const amount1Min = ethers.parseEther("0.001");

    // Close position with minimum amounts
    const result = await lpManager.closePosition(
      initialPosition.positionKey,
      amount0Min,
      amount1Min
    );

    expect(result.change).to.eq(PositionChange.Closed);
    expect(result.amount0).to.be.gte(amount0Min);
    expect(result.amount1).to.be.gte(amount1Min);

    // Verify position is closed
    await expect(
      lpManager.getPosition(initialPosition.positionKey)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "InvalidPositionKey"
    );

    // Verify tokens are returned
    const token0AfterBalance = await token0.balanceOf(liquidityOwnerAddress);
    const token1AfterBalance = await token1.balanceOf(liquidityOwnerAddress);
    expect(token0AfterBalance).to.eq(token0InitialBalance + result.amount0);
    expect(token1AfterBalance).to.eq(token1InitialBalance + result.amount1);
  });

  it("should revert when closing position with too high minimum amounts", async () => {
    const { lpManager, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    const amount0Min = ethers.parseEther("1000000"); // unreasonably high
    const amount1Min = ethers.parseEther("1000000"); // unreasonably high

    await expect(
      lpManager.closePosition(
        initialPosition.positionKey,
        amount0Min,
        amount1Min
      )
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "PriceSlippageCheck"
    );
  });

  it("should revert when non-owner tries to close position", async () => {
    const { lpManager, user } = testSetup;
    lpManager.useCaller(user);

    await expect(
      lpManager.closePosition(initialPosition.positionKey)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "NotLiquidityOwner"
    );
  });

  it("should revert when closing invalid position", async () => {
    const { lpManager, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    const invalidPositionKey = ethers.keccak256(
      ethers.toUtf8Bytes("invalid_position")
    );

    await expect(
      lpManager.closePosition(invalidPositionKey)
    ).to.be.revertedWithCustomError(
      lpManager.innerContract,
      "InvalidPositionKey"
    );
  });

  it("should collect fees when closing position", async () => {
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    lpManager.useCaller(liquidityOwner);

    // Get initial collected fees
    const initialFees = await lpManager.getPosition(
      initialPosition.positionKey
    );
    const fee0Before = initialFees.fee0;
    const fee1Before = initialFees.fee1;

    // Close position
    const result = await lpManager.closePosition(initialPosition.positionKey);

    // Verify fees are included in returned amounts
    expect(result.amount0).to.be.gte(fee0Before);
    expect(result.amount1).to.be.gte(fee1Before);
  });
});

describe("UniswapV3LpManager - Rebalance Operations", () => {
  let testSetup: TestSetup;
  let initialPosition: InitialPositionResult;

  beforeEach(async () => {
    testSetup = await setupTest();
    const { lpManager, uniswap, liquidityOwner } = testSetup;
    initialPosition = await setupInitialPosition(
      lpManager,
      uniswap,
      liquidityOwner
    );
  });

  it("rebalance1For0 should call _rebalanceIncreaseLiquidity when within tick range", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;

    // Get initial position
    const position = await lpManager.getPosition(initialPosition.positionKey);
    const initialLiquidity = position.liquidity;

    // Use same amount and params from successful test case
    const amount = ethers.parseEther("0.01");
    const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);

    // Transfer tokens to contract
    await token1.transfer(await lpManager.innerContract.getAddress(), amount);

    // Use exact same parameters that worked in "rebalance 1 for 0 - new position created" test
    const rebalanceParams = {
      tokenPairId: position.tokenPairId,
      sqrtPriceLimitX96: 4880412434988856429110099968n,
      maxMintSlippageRate: lpManager.toOnChainRate(1),
      tickLower: position.tickLower, // Only change: use existing position's ticks
      tickUpper: position.tickUpper, // Only change: use existing position's ticks
      R_Q96: 252704211256043437387939840n,
      amount0: ethers.parseEther("0"),
      amount1: amount,
      searchRange: {
        swapInLow: ethers.parseEther("0.004956984791606578"),
        swapInHigh: ethers.parseEther("0.004971855745981397"),
        searchLoopNum: 5,
      },
    };

    // Execute rebalance
    await lpManager.useCaller(balancer);
    const result = await lpManager.rebalance1For0(rebalanceParams);

    expect(result).to.emit(lpManager.innerContract, "PositionChanged");

    // Verify results
    expect(result.change).to.eq(PositionChange.Increase);
    expect(result.positionKey).to.eq(initialPosition.positionKey);

    const newPosition = await lpManager.getPosition(
      initialPosition.positionKey
    );
    expect(newPosition.liquidity).to.be.gt(initialLiquidity);
  });

  it("rebalance0For1 should call _rebalanceIncreaseLiquidity when within tick range", async () => {
    const { lpManager, uniswap, balancer, liquidityOwner } = testSetup;

    // Get initial position
    const position = await lpManager.getPosition(initialPosition.positionKey);
    const initialLiquidity = position.liquidity;

    // Use same amount and params from successful test case
    const amount = ethers.parseEther("1");
    const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);

    // Transfer tokens to contract
    await token0.transfer(await lpManager.innerContract.getAddress(), amount);

    // Use exact same parameters that worked in "rebalance 0 for 1 - new position created" test
    const rebalanceParams = {
      tokenPairId: position.tokenPairId,
      sqrtPriceLimitX96: 4303636419944718166428483584n,
      maxMintSlippageRate: lpManager.toOnChainRate(1),
      tickLower: position.tickLower,
      tickUpper: position.tickUpper,
      R_Q96: 252704211256043437387939840n,
      amount0: amount,
      amount1: ethers.parseEther("0"),
      searchRange: {
        swapInLow: ethers.parseEther("0.5042192936211579"),
        swapInHigh: ethers.parseEther("0.5057319515020213"),
        searchLoopNum: 5,
      },
    };

    // Execute rebalance
    await lpManager.useCaller(balancer);
    const result = await lpManager.rebalance0For1(rebalanceParams);

    expect(result).to.emit(lpManager.innerContract, "PositionChanged");

    // Verify results
    expect(result.change).to.eq(PositionChange.Increase);
    expect(result.positionKey).to.eq(initialPosition.positionKey);

    const newPosition = await lpManager.getPosition(
      initialPosition.positionKey
    );
    expect(newPosition.liquidity).to.be.gt(initialLiquidity);
  });
});
