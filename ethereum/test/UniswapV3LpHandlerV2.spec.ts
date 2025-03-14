import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { deployContractWithDeployer } from "../scripts/util";

describe("UniswapV3LpHandlerV2", function () {
  let supportedTokenPairs: Contract;
  let lpHandler: Contract;
  let lpManager: Contract;
  let mockWETH: Contract;
  let mockToken0: Contract;
  let mockToken1: Contract;
  let mockPool: Contract;
  let deployer: Signer;
  let balancer: Signer;
  let liquidityOwner: Signer;
  let user: Signer;
  let tokenPairId = 1;

  beforeEach(async function () {
    [deployer, balancer, liquidityOwner, user] = await ethers.getSigners();

    // Deploy mock contracts
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockWETH = await MockERC20.deploy("Wrapped Ether", "WETH", 18);
    mockToken0 = await MockERC20.deploy("Token0", "TK0", 18);
    mockToken1 = await MockERC20.deploy("Token1", "TK1", 18);

    supportedTokenPairs = await deployContractWithDeployer(
      deployer,
      "MockUniswapV3TokenPairs",
      [],
      false
    );

    mockPool = await deployContractWithDeployer(
      deployer,
      "MockUniswapV3Pool",
      [
        await mockToken0.getAddress(),
        await mockToken1.getAddress(),
        3000, // fee
      ],
      false
    );

    // Deploy LP Manager contract
    lpManager = await deployContractWithDeployer(
      deployer,
      "UniswapV3LpManager",
      [await mockPool.getAddress(), await mockWETH.getAddress()],
      false
    );

    // Deploy main contract
    lpHandler = await deployContractWithDeployer(
      deployer,
      "UniswapV3LpHandlerV2",
      [
        await supportedTokenPairs.getAddress(),
        await lpManager.getAddress(),
        await mockPool.getAddress(),
        await liquidityOwner.getAddress(),
        await balancer.getAddress(),
      ],
      false
    );

    await setupTokenPair();

    // Set permissions for LpManager
    // @ts-ignore
    await lpManager.connect(deployer).setCaller(await lpHandler.getAddress());

    // Mint tokens
    const amount = ethers.parseEther("1000");
    await mockToken0.mint(await liquidityOwner.getAddress(), amount);
    await mockToken1.mint(await liquidityOwner.getAddress(), amount);
    await mockWETH.mint(await liquidityOwner.getAddress(), amount);

    // Approve tokens
    await mockToken0
      .connect(liquidityOwner)
      // @ts-ignore
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
    await mockToken1
      .connect(liquidityOwner)
      // @ts-ignore
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
    await mockWETH
      .connect(liquidityOwner)
      // @ts-ignore
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
  });

  // Helper function: Setup token pair
  async function setupTokenPair() {
    const token0Address = await mockToken0.getAddress();
    const token1Address = await mockToken1.getAddress();
    const [sortedToken0, sortedToken1] =
      token0Address.toLowerCase() < token1Address.toLowerCase()
        ? [token0Address, token1Address]
        : [token1Address, token0Address];

    await supportedTokenPairs.addTokenPair(
      await mockPool.getAddress(),
      sortedToken0,
      sortedToken1,
      3000 // Fee
    );

    return { sortedToken0, sortedToken1 };
  }

  async function mintNewLiquidity(tokenPairId = 1) {
    const amount0 = ethers.parseEther("2"); // Increased amount0
    const amount1 = ethers.parseEther("0.5"); // Decreased amount1

    // Set initial liquidity in the mock pool
    await mockPool.setLiquidity(ethers.parseEther("10"));
    await mockPool.setSqrtPriceX96("79228162514264337593543950336"); // 1:1 price

    await lpHandler
      .connect(liquidityOwner)
      // @ts-ignore
      .mint(tokenPairId, -100, 100, amount0, amount1);
  }

  describe("Constructor & Initial State", function () {
    it("should correctly set the initial state", async function () {
      expect(await lpHandler.lpManager()).to.equal(
        await lpManager.getAddress()
      );
      expect(await lpHandler.liquidityOwner()).to.equal(
        await liquidityOwner.getAddress()
      );
      expect(await lpHandler.balancer()).to.equal(await balancer.getAddress());

      const params = await lpHandler.operationalParams();
      expect(params.maxMintSlippageRate).to.equal(30);
      expect(params.isCompoundFee).to.equal(true);
      expect(params.protocolFeeRate).to.equal(50);
    });
  });

  describe("Access Control", function () {
    it("only liquidityOwner can set a new lpManager", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setLpManager(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        // @ts-ignore
        lpHandler.connect(liquidityOwner).setLpManager(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .setLpManager(await user.getAddress());
      expect(await lpHandler.lpManager()).to.equal(await user.getAddress());
    });

    it("only liquidityOwner can set a new liquidityOwner", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setLiquidityOwner(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        // @ts-ignore
        lpHandler.connect(liquidityOwner).setLiquidityOwner(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .setLiquidityOwner(await user.getAddress());
      expect(await lpHandler.liquidityOwner()).to.equal(
        await user.getAddress()
      );
    });

    it("only liquidityOwner can set a new balancer", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setBalancer(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        // @ts-ignore
        lpHandler.connect(liquidityOwner).setBalancer(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .setBalancer(await user.getAddress());
      expect(await lpHandler.balancer()).to.equal(await user.getAddress());
    });
  });

  describe("Parameter Settings", function () {
    it("only liquidityOwner can set the protocol fee rate", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setProtocolFeeRate(100)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        // @ts-ignore
        lpHandler.connect(liquidityOwner).setProtocolFeeRate(1001)
      ).to.be.revertedWithCustomError(lpHandler, "RateTooHigh");

      // @ts-ignore
      await lpHandler.connect(liquidityOwner).setProtocolFeeRate(100);
      const params = await lpHandler.operationalParams();
      expect(params.protocolFeeRate).to.equal(100);
    });

    it("only balancer can set the max mint slippage rate", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setMaxMintSlippageRate(100)
      ).to.be.revertedWithCustomError(lpHandler, "NotBalancer");

      await expect(
        // @ts-ignore
        lpHandler.connect(balancer).setMaxMintSlippageRate(1001)
      ).to.be.revertedWithCustomError(lpHandler, "RateTooHigh");

      // @ts-ignore
      await lpHandler.connect(balancer).setMaxMintSlippageRate(100);
      const params = await lpHandler.operationalParams();
      expect(params.maxMintSlippageRate).to.equal(100);
    });

    it("only liquidityOwner can set the compound fee flag", async function () {
      await expect(
        // @ts-ignore
        lpHandler.connect(user).setCompoundFee(false)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      // @ts-ignore
      await lpHandler.connect(liquidityOwner).setCompoundFee(false);
      const params = await lpHandler.operationalParams();
      expect(params.isCompoundFee).to.equal(false);
    });
  });

  describe("Liquidity Management", function () {
    it("only liquidityOwner can mint new liquidity", async function () {
      const amount0 = ethers.parseEther("1");
      const amount1 = ethers.parseEther("1");

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .mint(tokenPairId, -100, 100, amount0, amount1)
      ).to.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
    });

    it("should mint new liquidity", async function () {
      const amount0 = ethers.parseEther("2");
      const amount1 = ethers.parseEther("0.5");
      await mintNewLiquidity();
      expect(await mockToken0.balanceOf(await lpHandler.getAddress())).to.equal(
        amount1
      );
      expect(await mockToken1.balanceOf(await lpHandler.getAddress())).to.equal(
        amount0
      );
    });

    it("should increase liquidity for existing position", async function () {
      const amount0 = ethers.parseEther("1");
      const amount1 = ethers.parseEther("1");
      const positionId = 1;

      await mintNewLiquidity();

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .increaseLiquidity(positionId, amount0, amount1)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .increaseLiquidity(positionId, amount0, amount1);

      expect(await mockToken0.balanceOf(await lpHandler.getAddress())).to.equal(
        ethers.parseEther("3")
      );
      expect(await mockToken1.balanceOf(await lpHandler.getAddress())).to.equal(
        ethers.parseEther("1.5")
      );
    });

    it("should decrease liquidity for existing position", async function () {
      const amount0Min = ethers.parseEther("0.5"); // Increased minimum amount
      const amount1Min = ethers.parseEther("0.5"); // Increased minimum amount
      const positionId = 1;
      const percentage = 10; // 50%

      await mintNewLiquidity();

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .decreaseLiquidity(positionId, percentage, amount0Min, amount1Min)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .decreaseLiquidity(positionId, percentage, amount0Min, amount1Min);

      // Check that tokens were transferred back to liquidityOwner
      expect(
        await mockToken0.balanceOf(await liquidityOwner.getAddress())
      ).to.be.gt(0);
      expect(
        await mockToken1.balanceOf(await liquidityOwner.getAddress())
      ).to.be.gt(0);
    });
  });

  describe("Fee Management", function () {
    it("should collect fees for a single position", async function () {
      const positionId = 1;

      await mintNewLiquidity();

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .collectAllFees(positionId)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        lpHandler
          .connect(liquidityOwner)
          // @ts-ignore
          .collectAllFees(positionId)
      ).to.emit(lpHandler, "FeesCollected");
    });

    it("should collect fees for multiple positions", async function () {
      const positionIds = [1];

      await mintNewLiquidity();

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .batchCollectFees(positionIds)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await lpHandler
        .connect(liquidityOwner)
        // @ts-ignore
        .batchCollectFees(positionIds);
    });
  });

  describe("Position Rebalancing", function () {
    it("should rebalance position with new parameters", async function () {
      const rebalanceParams = {
        positionId: 1,
        amount0WithdrawMin: ethers.parseEther("1.1"),
        amount1WithdrawMin: ethers.parseEther("1.1"),
        swapSlippage: 50, // 5%
        newAmount0: ethers.parseEther("6"),  // Increased amount0
        newAmount1: ethers.parseEther("1"),  // Decreased amount1
        tickLower: -100,
        tickUpper: 100,
      };

      await mintNewLiquidity();

      // Mint tokens to balancer
      await mockToken0.mint(await balancer.getAddress(), ethers.parseEther("20"));
      await mockToken1.mint(await balancer.getAddress(), ethers.parseEther("20"));

      // Approve tokens for both pool and handler
      await mockToken0
        .connect(balancer)
        // @ts-ignore
        .approve(await lpHandler.getAddress(), ethers.MaxUint256);
      await mockToken1
        .connect(balancer)
        // @ts-ignore
        .approve(await lpHandler.getAddress(), ethers.MaxUint256);
      await mockToken0
        .connect(balancer)
        // @ts-ignore
        .approve(await mockPool.getAddress(), ethers.MaxUint256);
      await mockToken1
        .connect(balancer)
        // @ts-ignore
        .approve(await mockPool.getAddress(), ethers.MaxUint256);

      // Set mock pool state to enable swapping
      await mockPool.setLiquidity(ethers.parseEther("100"));
      await mockPool.setSqrtPriceX96("79228162514264337593543950336"); // 1:1 price

      // Collect fees and reduce liquidity first
      await lpHandler
        .connect(balancer)
        // @ts-ignore
        .collectFeesAndReduceLiquidity(
          rebalanceParams.positionId,
          rebalanceParams.swapSlippage,
          rebalanceParams.amount0WithdrawMin,
          rebalanceParams.amount1WithdrawMin
        );

      // Perform rebalance
      await expect(
        lpHandler
          .connect(balancer)
          // @ts-ignore
          .rebalance(rebalanceParams)
      ).to.emit(lpHandler, "PositionRebalanced");
    });

    it("should collect fees and reduce liquidity", async function () {
      const positionId = 1;
      const amount0Min = ethers.parseEther("0.1");
      const amount1Min = ethers.parseEther("0.1");
      const swapSlippage = 50;

      await mintNewLiquidity();

      await expect(
        lpHandler
          .connect(user)
          // @ts-ignore
          .collectFeesAndReduceLiquidity(
            positionId,
            swapSlippage,
            amount0Min,
            amount1Min
          )
      ).to.be.revertedWithCustomError(lpHandler, "NotBalancer");

      await lpHandler
        .connect(balancer)
        // @ts-ignore
        .collectFeesAndReduceLiquidity(
          positionId,
          swapSlippage,
          amount0Min,
          amount1Min
        );
    });

    it("should validate tick range for rebalancing", async function () {
      const invalidRebalanceParams = {
        positionId: 1,
        amount0WithdrawMin: ethers.parseEther("0.1"),
        amount1WithdrawMin: ethers.parseEther("0.1"),
        swapSlippage: 50,
        newAmount0: ethers.parseEther("2"),
        newAmount1: ethers.parseEther("2"),
        tickLower: 100,
        tickUpper: -100, // Invalid: upper tick is less than lower tick
      };

      await expect(
        lpHandler
          .connect(balancer)
          // @ts-ignore
          .rebalance(invalidRebalanceParams)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidTickRange");
    });
  });
});
