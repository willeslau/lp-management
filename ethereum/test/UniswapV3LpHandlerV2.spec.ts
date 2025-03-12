import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { deployContractWithDeployer } from "../scripts/util";

describe("UniswapV3LpHandlerV2", function () {
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

  beforeEach(async function () {
    [deployer, balancer, liquidityOwner, user] = await ethers.getSigners();

    // Deploy mock contracts
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockWETH = await MockERC20.deploy("Wrapped Ether", "WETH", 18);
    mockToken0 = await MockERC20.deploy("Token0", "TK0", 18);
    mockToken1 = await MockERC20.deploy("Token1", "TK1", 18);

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
        await lpManager.getAddress(),
        await mockPool.getAddress(),
        await liquidityOwner.getAddress(),
        await balancer.getAddress(),
      ],
      false
    );

    // Set permissions for LpManager
    await lpManager.connect(deployer).setCaller(await lpHandler.getAddress());

    // Mint tokens
    const amount = ethers.parseEther("1000");
    await mockToken0.mint(await liquidityOwner.getAddress(), amount);
    await mockToken1.mint(await liquidityOwner.getAddress(), amount);
    await mockWETH.mint(await liquidityOwner.getAddress(), amount);

    // Approve tokens
    await mockToken0
      .connect(liquidityOwner)
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
    await mockToken1
      .connect(liquidityOwner)
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
    await mockWETH
      .connect(liquidityOwner)
      .approve(await lpHandler.getAddress(), ethers.MaxUint256);
  });

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
        lpHandler.connect(user).setLpManager(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        lpHandler.connect(liquidityOwner).setLpManager(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        .setLpManager(await user.getAddress());
      expect(await lpHandler.lpManager()).to.equal(await user.getAddress());
    });

    it("only liquidityOwner can set a new liquidityOwner", async function () {
      await expect(
        lpHandler.connect(user).setLiquidityOwner(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        lpHandler.connect(liquidityOwner).setLiquidityOwner(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        .setLiquidityOwner(await user.getAddress());
      expect(await lpHandler.liquidityOwner()).to.equal(
        await user.getAddress()
      );
    });

    it("only liquidityOwner can set a new balancer", async function () {
      await expect(
        lpHandler.connect(user).setBalancer(await user.getAddress())
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        lpHandler.connect(liquidityOwner).setBalancer(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");

      await lpHandler
        .connect(liquidityOwner)
        .setBalancer(await user.getAddress());
      expect(await lpHandler.balancer()).to.equal(await user.getAddress());
    });
  });

  describe("Parameter Settings", function () {
    it("only liquidityOwner can set the protocol fee rate", async function () {
      await expect(
        lpHandler.connect(user).setProtocolFeeRate(100)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await expect(
        lpHandler.connect(liquidityOwner).setProtocolFeeRate(1001)
      ).to.be.revertedWithCustomError(lpHandler, "RateTooHigh");

      await lpHandler.connect(liquidityOwner).setProtocolFeeRate(100);
      const params = await lpHandler.operationalParams();
      expect(params.protocolFeeRate).to.equal(100);
    });

    it("only balancer can set the max mint slippage rate", async function () {
      await expect(
        lpHandler.connect(user).setMaxMintSlippageRate(100)
      ).to.be.revertedWithCustomError(lpHandler, "NotBalancer");

      await expect(
        lpHandler.connect(balancer).setMaxMintSlippageRate(1001)
      ).to.be.revertedWithCustomError(lpHandler, "RateTooHigh");

      await lpHandler.connect(balancer).setMaxMintSlippageRate(100);
      const params = await lpHandler.operationalParams();
      expect(params.maxMintSlippageRate).to.equal(100);
    });

    it("only liquidityOwner can set the compound fee flag", async function () {
      await expect(
        lpHandler.connect(user).setCompoundFee(false)
      ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");

      await lpHandler.connect(liquidityOwner).setCompoundFee(false);
      const params = await lpHandler.operationalParams();
      expect(params.isCompoundFee).to.equal(false);
    });
  });

  describe("Liquidity Management", function () {
    it("only liquidityOwner can mint new liquidity", async function () {
      const amount0 = ethers.parseEther("1");
      const amount1 = ethers.parseEther("1");

      // Add token pair
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();

      await expect(
        lpHandler
          .connect(user)
          .mint(token0Address, token1Address, 3000, -100, 100, amount0, amount1)
      ).to.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
    });
  });
});
