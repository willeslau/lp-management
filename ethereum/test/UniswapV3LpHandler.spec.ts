import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { deployContractWithDeployer } from "../scripts/util";
import "@nomicfoundation/hardhat-chai-matchers";

describe("UniswapV3LpHandler", () => {
  // Shared variable declarations
  let lpHandler: Contract;
  let nonfungiblePositionManager: Contract;
  let supportedTokenPairs: Contract;
  let mockToken0: Contract;
  let mockToken1: Contract;
  let mockSwap: Contract;
  let deployer: Signer;
  let liquidityOwner: Signer;
  let balancer: Signer;
  let user: Signer;
  let deployerAddress: string;
  let liquidityOwnerAddress: string;
  let balancerAddress: string;
  let userAddress: string;

  // Helper function: Setup test environment
  async function setupTestEnvironment() {
    [deployer, liquidityOwner, balancer, user] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    liquidityOwnerAddress = await liquidityOwner.getAddress();
    balancerAddress = await balancer.getAddress();
    userAddress = await user.getAddress();

    // Deploy mock contracts
    mockToken0 = await deployContractWithDeployer(
      deployer,
      "MockERC20",
      ["Token0", "TK0", 18],
      false
    );
    mockToken1 = await deployContractWithDeployer(
      deployer,
      "MockERC20",
      ["Token1", "TK1", 18],
      false
    );

    // Deploy mock position manager and token pairs
    nonfungiblePositionManager = await deployContractWithDeployer(
      deployer,
      "MockNonfungiblePositionManager",
      [],
      false
    );
    supportedTokenPairs = await deployContractWithDeployer(
      deployer,
      "MockUniswapV3TokenPairs",
      [],
      false
    );
    mockSwap = await deployContractWithDeployer(
      deployer,
      "MockUniswapV3Pool",
      [
        await mockToken0.getAddress(),
        await mockToken1.getAddress(),
        3000, // fee
      ],
      false
    );

    // Deploy the contract under test
    lpHandler = await deployContractWithDeployer(
      deployer,
      "UniswapV3LpHandler",
      [
        await nonfungiblePositionManager.getAddress(),
        await supportedTokenPairs.getAddress(),
        liquidityOwnerAddress, // Liquidity owner
        balancerAddress, // Balancer
        await nonfungiblePositionManager.getAddress(), // Position NFT address
        await mockSwap.getAddress(), // Swap router
      ],
      false
    );
  }

  // Helper function: Setup token pair
  async function setupTokenPair() {
    const token0Address = await mockToken0.getAddress();
    const token1Address = await mockToken1.getAddress();
    const [sortedToken0, sortedToken1] =
      token0Address.toLowerCase() < token1Address.toLowerCase()
        ? [token0Address, token1Address]
        : [token1Address, token0Address];

    await supportedTokenPairs.addTokenPair(
      sortedToken0,
      sortedToken1,
      3000 // Fee
    );

    return { sortedToken0, sortedToken1 };
  }

  // Helper function: Mint new liquidity position
  async function mintNewPosition(
    amount0: bigint,
    amount1: bigint,
    tickLower: number,
    tickUpper: number
  ) {
    // Ensure token pair is set up
    await setupTokenPair();

    // Mint tokens for user
    await mockToken0.mint(liquidityOwnerAddress, amount0 * 2n);
    await mockToken1.mint(liquidityOwnerAddress, amount1 * 2n);

    // Approve tokens for LP handler
    await mockToken0
      .connect(liquidityOwner)
      // @ts-ignore
      .approve(await lpHandler.getAddress(), amount0 * 2n);
    await mockToken1
      .connect(liquidityOwner)
      // @ts-ignore
      .approve(await lpHandler.getAddress(), amount1 * 2n);

    // Call mintNewPosition
    // @ts-ignore
    await lpHandler.connect(liquidityOwner).mintNewPosition(
      1, // Token pair ID
      amount0,
      amount1,
      tickLower,
      tickUpper
    );

    // Return token ID
    return 1; // Default token ID in mock contract
  }

  // Helper function: Setup position details
  async function setupPositionDetails(
    tokenId: number,
    liquidity: bigint,
    tickLower: number,
    tickUpper: number
  ) {
    const token0Address = await mockToken0.getAddress();
    const token1Address = await mockToken1.getAddress();
    const [sortedToken0, sortedToken1] =
      token0Address.toLowerCase() < token1Address.toLowerCase()
        ? [token0Address, token1Address]
        : [token1Address, token0Address];

    await nonfungiblePositionManager.setPositionDetails(
      tokenId,
      sortedToken0,
      sortedToken1,
      tickLower,
      tickUpper,
      liquidity,
      3000
    );
  }

  beforeEach(async () => {
    await setupTestEnvironment();
  });

  // Basic configuration test group
  describe("Initialization and basic configuration", () => {
    it("Should initialize with correct values", async () => {
      // For non-public state variables, we cannot access them directly
      // Instead, we check other public variables and parameters
      expect(await lpHandler.nonfungiblePositionManager()).to.equal(
        await nonfungiblePositionManager.getAddress()
      );
      expect(await lpHandler.supportedTokenPairs()).to.equal(
        await supportedTokenPairs.getAddress()
      );
      expect(await lpHandler.swap()).to.equal(await mockSwap.getAddress());

      // Check initial operational parameters
      const params = await lpHandler.operationalParams();
      expect(params.maxMintSlippageRate).to.equal(30n); // 3%
      expect(params.isCompoundFee).to.be.true;
      expect(params.protocolFeeRate).to.equal(50n); // 5%
    });
  });

  // Permission management test group
  describe("Permission management", () => {
    describe("Liquidity owner permissions", () => {
      it("Should allow liquidity owner to set protocol fee rate", async () => {
        const newRate = 100; // 10%
        // @ts-ignore
        await lpHandler.connect(liquidityOwner).setProtocolFeeRate(newRate);
        const params = await lpHandler.operationalParams();
        expect(params.protocolFeeRate).to.equal(100n);
      });

      it("Should revert when non-owner tries to set protocol fee rate", async () => {
        const newRate = 100;
        await expect(
          // @ts-ignore
          lpHandler.connect(deployer).setProtocolFeeRate(newRate)
        ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
      });

      it("Should revert when setting invalid protocol fee rate", async () => {
        const invalidRate = 1001; // > 100%
        await expect(
          // @ts-ignore
          lpHandler.connect(liquidityOwner).setProtocolFeeRate(invalidRate)
        ).to.be.revertedWithCustomError(lpHandler, "RateTooHigh");
      });

      it("Should allow liquidity owner to change owner address", async () => {
        const newOwner = await balancer.getAddress();
        // @ts-ignore
        await lpHandler.connect(liquidityOwner).setLiquidityOwner(newOwner);

        // Since we cannot directly access the liquidityOwner state variable,
        // We can verify the change by attempting to call functions that require liquidityOwner permission
        // If balancer can now call setProtocolFeeRate, it means ownership has been successfully transferred
        const newRate = 200; // 20%
        // @ts-ignore
        await lpHandler.connect(balancer).setProtocolFeeRate(newRate);
        const params = await lpHandler.operationalParams();
        expect(params.protocolFeeRate).to.equal(200n);
      });

      it("Should revert when setting invalid owner address", async () => {
        await expect(
          lpHandler
            .connect(liquidityOwner)
            // @ts-ignore
            .setLiquidityOwner(ethers.ZeroAddress)
        ).to.be.revertedWithCustomError(lpHandler, "InvalidAddress");
      });

      it("Should allow liquidity owner to toggle compound fee setting", async () => {
        // Initial setting is true
        let params = await lpHandler.operationalParams();
        expect(params.isCompoundFee).to.be.true;

        // Toggle to false
        // @ts-ignore
        await lpHandler.connect(liquidityOwner).setCompoundFee(false);
        params = await lpHandler.operationalParams();
        expect(params.isCompoundFee).to.be.false;

        // Toggle back to true
        // @ts-ignore
        await lpHandler.connect(liquidityOwner).setCompoundFee(true);
        params = await lpHandler.operationalParams();
        expect(params.isCompoundFee).to.be.true;
      });

      it("should revert when non-owner tries to toggle compound fee setting", async () => {
        await expect(
          // @ts-ignore
          lpHandler.connect(deployer).setCompoundFee(false)
        ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
      });
    });

    describe("Balancer permissions", () => {
      it("should allow balancer to set max mint slippage rate", async () => {
        const newRate = 50; // 5%
        // @ts-ignore
        await lpHandler.connect(balancer).setMaxMintSlippageRate(newRate);
        const params = await lpHandler.operationalParams();
        expect(params.maxMintSlippageRate).to.equal(50n);
      });

      it("should revert when non-balancer tries to set max mint slippage rate", async () => {
        const newRate = 50;
        await expect(
          // @ts-ignore
          lpHandler.connect(liquidityOwner).setMaxMintSlippageRate(newRate)
        ).to.be.revertedWithCustomError(lpHandler, "NotBalancer");
      });

      it("should revert when non-balancer tries to rebalance", async () => {
        const rebalanceParams = {
          tokenId: 1,
          amount0WithdrawMin: 0,
          amount1WithdrawMin: 0,
          swapSlippage: 50,
          newAmount0: ethers.parseEther("8"),
          newAmount1: ethers.parseEther("8"),
          tickLower: -200,
          tickUpper: 200,
        };

        await expect(
          // @ts-ignore
          lpHandler.connect(liquidityOwner).rebalance(rebalanceParams)
        )
          .to.be.revertedWithCustomError(lpHandler, "NotBalancer")
          .withArgs(liquidityOwnerAddress);
      });
    });
  });

  // Liquidity operation test group
  describe("Liquidity operations", () => {
    describe("Mint new position", () => {
      it("should successfully mint new position", async () => {
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Verify deposit is created
        const deposit = await lpHandler.deposits(tokenId);
        expect(deposit.tokenPair).to.equal(1n);
        expect(deposit.liquidity > 0n).to.be.true;
      });
    });

    describe("Increase liquidity", () => {
      it("should successfully increase liquidity", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Increase liquidity
        const additionalAmount0 = ethers.parseEther("5");
        const additionalAmount1 = ethers.parseEther("5");

        // Approve additional tokens
        await mockToken0
          .connect(liquidityOwner)
          // @ts-ignore
          .approve(await lpHandler.getAddress(), additionalAmount0);
        await mockToken1
          .connect(liquidityOwner)
          // @ts-ignore
          .approve(await lpHandler.getAddress(), additionalAmount1);

        // Mint additional tokens
        await mockToken0.mint(liquidityOwnerAddress, additionalAmount0);
        await mockToken1.mint(liquidityOwnerAddress, additionalAmount1);

        // Call increaseLiquidity
        await lpHandler
          .connect(liquidityOwner)
          // @ts-ignore
          .increaseLiquidity(tokenId, additionalAmount0, additionalAmount1);

        // Verify liquidity has increased
        const updatedDeposit = await lpHandler.deposits(tokenId);
        expect(updatedDeposit.liquidity).to.be.gt(initialLiquidity);
      });

      it("should revert when non-owner tries to increase liquidity", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Increase liquidity
        const additionalAmount0 = ethers.parseEther("5");
        const additionalAmount1 = ethers.parseEther("5");

        // Approve additional tokens
        await mockToken0
          .connect(user)
          // @ts-ignore
          .approve(await lpHandler.getAddress(), additionalAmount0);
        await mockToken1
          .connect(user)
          // @ts-ignore
          .approve(await lpHandler.getAddress(), additionalAmount1);

        // Mint additional tokens
        await mockToken0.mint(userAddress, additionalAmount0);
        await mockToken1.mint(userAddress, additionalAmount1);

        // Attempt to call increaseLiquidity, should fail
        await expect(
          lpHandler
            .connect(user)
            // @ts-ignore
            .increaseLiquidity(tokenId, additionalAmount0, additionalAmount1)
        ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
      });
    });

    describe("Collect fees", () => {
      it("should successfully collect fees", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Simulate collected fees
        const fee0 = ethers.parseEther("1");
        const fee1 = ethers.parseEther("1.5");
        await nonfungiblePositionManager.setCollectAmounts(fee0, fee1);

        // Call collectAllFees
        // @ts-ignore
        await lpHandler.connect(liquidityOwner).collectAllFees(tokenId);

        // Verify fees have been collected
        const updatedDeposit = await lpHandler.deposits(tokenId);
        expect(updatedDeposit.fee0).to.equal(fee0);
        expect(updatedDeposit.fee1).to.equal(fee1);
      });

      it("should revert when non-owner tries to collect fees", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Simulate collected fees
        const fee0 = ethers.parseEther("1");
        const fee1 = ethers.parseEther("1.5");
        await nonfungiblePositionManager.setCollectAmounts(fee0, fee1);

        // Attempt to call collectAllFees, should fail
        await expect(
          // @ts-ignore
          lpHandler.connect(user).collectAllFees(tokenId)
        ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
      });
    });

    describe("Decrease liquidity", () => {
      it("should successfully decrease liquidity", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Decrease liquidity - using percentage value 500 represents 50%
        const percentageToRemove = 500; // 50%
        const amount0Min = 0;
        const amount1Min = 0;

        // Simulate return values for decreasing liquidity
        const returnedAmount0 = ethers.parseEther("4");
        const returnedAmount1 = ethers.parseEther("4");
        await nonfungiblePositionManager.setDecreaseAmounts(
          returnedAmount0,
          returnedAmount1
        );

        // Call decreaseLiquidity
        await lpHandler
          .connect(liquidityOwner)
          // @ts-ignore
          .decreaseLiquidity(
            tokenId,
            percentageToRemove,
            amount0Min,
            amount1Min
          );

        // Verify liquidity has decreased
        const updatedDeposit = await lpHandler.deposits(tokenId);
        expect(updatedDeposit.liquidity).to.not.equal(initialLiquidity);
      });

      it("should revert when non-owner tries to decrease liquidity", async () => {
        // First, set up token pair and mint position
        const amount0 = ethers.parseEther("10");
        const amount1 = ethers.parseEther("10");
        const tickLower = -100;
        const tickUpper = 100;
        const tokenId = await mintNewPosition(
          amount0,
          amount1,
          tickLower,
          tickUpper
        );

        // Get initial liquidity
        const initialDeposit = await lpHandler.deposits(tokenId);
        const initialLiquidity = initialDeposit.liquidity;

        // Set up position details for mock NFT manager contract
        await setupPositionDetails(
          tokenId,
          initialLiquidity,
          tickLower,
          tickUpper
        );

        // Decrease liquidity - using percentage value 500 represents 50%
        const percentageToRemove = 500; // 50%
        const amount0Min = 0;
        const amount1Min = 0;

        // Attempt to call decreaseLiquidity, should fail
        await expect(
          lpHandler
            .connect(user)
            // @ts-ignore
            .decreaseLiquidity(
              tokenId,
              percentageToRemove,
              amount0Min,
              amount1Min
            )
        ).to.be.revertedWithCustomError(lpHandler, "NotLiquidityOwner");
      });
    });
  });

  // Rebalance test group
  describe("Rebalance operations", () => {
    it("should allow balancer to perform rebalancing", async () => {
      // First, set up token pair and mint position
      const amount0 = ethers.parseEther("10");
      const amount1 = ethers.parseEther("10");
      const tickLower = -100;
      const tickUpper = 100;
      const tokenId = await mintNewPosition(
        amount0,
        amount1,
        tickLower,
        tickUpper
      );

      // Get initial liquidity
      const initialDeposit = await lpHandler.deposits(tokenId);
      const initialLiquidity = initialDeposit.liquidity;

      // Set up position details for mock NFT manager contract
      await setupPositionDetails(
        tokenId,
        initialLiquidity,
        tickLower,
        tickUpper
      );

      // Mock return value for liquidity decrease
      const returnedAmount0 = ethers.parseEther("8");
      const returnedAmount1 = ethers.parseEther("8");
      await nonfungiblePositionManager.setDecreaseAmounts(
        returnedAmount0,
        returnedAmount1
      );

      const lpHandlerAddress = await lpHandler.getAddress();
      const mockSwapAddress = await mockSwap.getAddress();

      // Mint tokens to lpHandler for the decrease liquidity operation
      await mockToken0.mint(lpHandlerAddress, returnedAmount0);
      await mockToken1.mint(lpHandlerAddress, returnedAmount1);

      // Set rebalancing parameters
      const rebalanceParams = {
        tokenId: tokenId,
        amount0WithdrawMin: 0,
        amount1WithdrawMin: 0,
        swapSlippage: 50, // 5%
        newAmount0: ethers.parseEther("6"), // Reduce token0 amount
        newAmount1: ethers.parseEther("12"), // Increase token1 amount
        tickLower: -200,
        tickUpper: 200,
      };

      const amount = ethers.parseEther("20");
      // Mint extra tokens to mock swap router for the swap operation
      await mockToken0.mint(mockSwapAddress, amount);
      await mockToken1.mint(mockSwapAddress, amount);

      // Mint tokens for balancer
      await mockToken0.mint(balancerAddress, amount);
      await mockToken1.mint(balancerAddress, amount);

      // Approve tokens for rebalancing
      // @ts-ignore
      await mockToken0.connect(balancer).approve(lpHandlerAddress, amount);
      // @ts-ignore
      await mockToken1.connect(balancer).approve(lpHandlerAddress, amount);

      // Call rebalance function
      // @ts-ignore
      await lpHandler.connect(balancer).rebalance(rebalanceParams);

      // Verify deposit has been updated
      const updatedDeposit = await lpHandler.deposits(tokenId);
      expect(updatedDeposit.liquidity).to.not.equal(initialLiquidity);
    });

    it("should revert with invalid rebalancing parameters", async () => {
      // First, set up token pair and mint position
      const amount0 = ethers.parseEther("10");
      const amount1 = ethers.parseEther("10");
      const tickLower = -100;
      const tickUpper = 100;
      const tokenId = await mintNewPosition(
        amount0,
        amount1,
        tickLower,
        tickUpper
      );

      // Get initial liquidity
      const initialDeposit = await lpHandler.deposits(tokenId);
      const initialLiquidity = initialDeposit.liquidity;

      // Set up position details for mock NFT manager contract
      await setupPositionDetails(
        tokenId,
        initialLiquidity,
        tickLower,
        tickUpper
      );

      // Set invalid rebalancing parameters (triggering NotSwapable error)
      // Set new amounts equal to original to avoid triggering swap
      const invalidRebalanceParams = {
        tokenId: tokenId,
        amount0WithdrawMin: 0,
        amount1WithdrawMin: 0,
        swapSlippage: 50, // 5%, valid value
        newAmount0: amount0, // same as original amount
        newAmount1: amount1, // same as original amount
        tickLower: -200,
        tickUpper: 200,
      };

      // Attempt to call rebalance, should fail as no swap needed
      await expect(
        // @ts-ignore
        lpHandler.connect(balancer).rebalance(invalidRebalanceParams)
      ).to.be.revertedWithCustomError(lpHandler, "NotSwapable");
    });
  });
});
