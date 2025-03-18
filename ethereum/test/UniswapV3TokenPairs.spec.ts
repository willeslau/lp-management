import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import {
  deployContractWithDeployer,
  sortTokenAddresses,
} from "../scripts/util";

describe("UniswapV3TokenPairs", function () {
  let tokenPairs: Contract;
  let mockPool: Contract;
  let mockToken0: Contract;
  let mockToken1: Contract;
  let deployer: Signer;
  let user: Signer;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Deploy mock contracts
    const MockERC20 = await ethers.getContractFactory("MockERC20");
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

    // Deploy the contract under test
    tokenPairs = await deployContractWithDeployer(
      deployer,
      "UniswapV3TokenPairs",
      [],
      false
    );
  });

  describe("Token Pair Management", function () {
    it("should add a new token pair correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const fee = 3000;

      // Sort token addresses before adding pair
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );
      await expect(
        tokenPairs.addTokenPair(poolAddress, sortedToken0, sortedToken1, fee)
      )
        .to.emit(tokenPairs, "TokenPairAdded")
        .withArgs(1, sortedToken0, sortedToken1, poolAddress, fee);

      const pair = await tokenPairs.getTokenPair(1n);
      expect(pair.id).to.equal(1);
      expect(pair.pool).to.equal(poolAddress);
      expect(pair.token0).to.equal(sortedToken0);
      expect(pair.token1).to.equal(sortedToken1);
      expect(pair.poolFee).to.equal(fee);
    });

    it("should revert when adding duplicate token pair", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const fee = 3000;

      // Sort token addresses before adding pair
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        fee
      );

      await expect(
        tokenPairs.addTokenPair(poolAddress, sortedToken0, sortedToken1, fee)
      ).to.be.revertedWithCustomError(tokenPairs, "PairAlreadyExists");
    });

    it("should revert when adding with invalid addresses", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const fee = 3000;

      // Sort token addresses
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      await expect(
        tokenPairs.addTokenPair(
          ethers.ZeroAddress,
          sortedToken0,
          sortedToken1,
          fee
        )
      ).to.be.revertedWithCustomError(tokenPairs, "InvalidPoolAddress");

      await expect(
        tokenPairs.addTokenPair(
          poolAddress,
          ethers.ZeroAddress,
          sortedToken1,
          fee
        )
      ).to.be.revertedWithCustomError(tokenPairs, "InvalidTokenAddress");

      await expect(
        tokenPairs.addTokenPair(
          poolAddress,
          sortedToken0,
          ethers.ZeroAddress,
          fee
        )
      ).to.be.revertedWithCustomError(tokenPairs, "InvalidTokenAddress");
    });
  });

  describe("Token Pair Queries", function () {
    beforeEach(async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();

      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );
      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        3000
      );
    });

    it("should get token pair by ID correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );
      const pair = await tokenPairs.getTokenPair(1);
      expect(pair.id).to.equal(1);
      expect(pair.pool).to.equal(await mockPool.getAddress());
      expect(pair.token0).to.equal(sortedToken0);
      expect(pair.token1).to.equal(sortedToken1);
      expect(pair.poolFee).to.equal(3000);
    });

    it("should get token pair ID by tokens correctly", async function () {
      const pairId = await tokenPairs.getTokenPairId(
        await mockToken0.getAddress(),
        await mockToken1.getAddress()
      );
      expect(pairId).to.equal(1);
    });

    it("should check if token pair is supported", async function () {
      const isSupported = await tokenPairs.isTokenPairSupported(
        await mockToken0.getAddress(),
        await mockToken1.getAddress()
      );
      expect(isSupported).to.be.true;

      const notSupported = await tokenPairs.isTokenPairSupported(
        await mockToken0.getAddress(),
        ethers.ZeroAddress
      );
      expect(notSupported).to.be.false;
    });

    it("should get all token pairs correctly", async function () {
      const pairs = await tokenPairs.getAllTokenPairs();
      expect(pairs.length).to.equal(1);
      expect(pairs[0].id).to.equal(1);
    });

    it("should get token pair addresses correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );
      const [token0, token1] = await tokenPairs.getTokenPairAddresses(1);
      expect(token0).to.equal(sortedToken0);
      expect(token1).to.equal(sortedToken1);
    });
  });

  describe("Access Control", function () {
    it("should only allow owner to add token pairs", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const fee = 3000;

      await expect(
        tokenPairs
          .connect(user)
          // @ts-ignore
          .addTokenPair(poolAddress, token0Address, token1Address, fee)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Token Pair ID Management", function () {
    it("should handle token pair ID increments correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      // Add first pair
      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        3000
      );
      expect(
        await tokenPairs.getTokenPairId(token0Address, token1Address)
      ).to.equal(1);

      // Add second pair with different fee
      const mockToken2 = await (
        await ethers.getContractFactory("MockERC20")
      ).deploy("Token2", "TK2", 18);
      const token2Address = await mockToken2.getAddress();
      const [newSortedToken0, newSortedToken1] = sortTokenAddresses(
        token0Address,
        token2Address
      );

      await tokenPairs.addTokenPair(
        poolAddress,
        newSortedToken0,
        newSortedToken1,
        500
      );
      expect(
        await tokenPairs.getTokenPairId(token0Address, token2Address)
      ).to.equal(2);
    });

    it("should validate token pair ID support correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        3000
      );

      expect(await tokenPairs.isSupportTokenPair(1)).to.be.true;
      expect(await tokenPairs.isSupportTokenPair(0)).to.be.false;
      expect(await tokenPairs.isSupportTokenPair(2)).to.be.false;
    });

    it("should handle invalid token pair IDs correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        3000
      );

      const pair = await tokenPairs.getTokenPair(0);
      expect(pair.id).to.equal(0);
      expect(pair.pool).to.equal(ethers.ZeroAddress);

      const [token0, token1] = await tokenPairs.getTokenPairAddresses(0);
      expect(token0).to.equal(ethers.ZeroAddress);
      expect(token1).to.equal(ethers.ZeroAddress);
    });

    it("should handle getTokenPairId with non-existent pairs", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const mockToken2 = await (
        await ethers.getContractFactory("MockERC20")
      ).deploy("Token2", "TK2", 18);
      const token2Address = await mockToken2.getAddress();

      expect(
        await tokenPairs.getTokenPairId(token0Address, token1Address)
      ).to.equal(0);
      expect(
        await tokenPairs.getTokenPairId(token0Address, token2Address)
      ).to.equal(0);
      expect(
        await tokenPairs.getTokenPairId(ethers.ZeroAddress, token0Address)
      ).to.equal(0);
      expect(
        await tokenPairs.getTokenPairId(token0Address, ethers.ZeroAddress)
      ).to.equal(0);
      expect(
        await tokenPairs.getTokenPairId(ethers.ZeroAddress, ethers.ZeroAddress)
      ).to.equal(0);
    });

    it("should handle getTokenPairId with reversed token order", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );

      await tokenPairs.addTokenPair(
        poolAddress,
        sortedToken0,
        sortedToken1,
        3000
      );

      const pairId1 = await tokenPairs.getTokenPairId(
        token0Address,
        token1Address
      );
      const pairId2 = await tokenPairs.getTokenPairId(
        token1Address,
        token0Address
      );
      expect(pairId1).to.equal(pairId2);
      expect(pairId1).to.equal(1);
    });

    it("should handle getTokenPairId with same token addresses", async function () {
      const token0Address = await mockToken0.getAddress();
      expect(
        await tokenPairs.getTokenPairId(token0Address, token0Address)
      ).to.equal(0);
    });
  });

  describe("Token Address Sorting", function () {
    it("should revert when adding token pair with unsorted addresses", async function () {
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      const poolAddress = await mockPool.getAddress();

      // Intentionally use unsorted addresses
      const [sortedToken0, sortedToken1] = sortTokenAddresses(
        token0Address,
        token1Address
      );
      await expect(
        tokenPairs.addTokenPair(poolAddress, sortedToken1, sortedToken0, 3000)
      ).to.be.revertedWithCustomError(tokenPairs, "TokenAddressesNotSorted");
    });

    it("should handle same token addresses correctly", async function () {
      const token0Address = await mockToken0.getAddress();
      const poolAddress = await mockPool.getAddress();

      await expect(
        tokenPairs.addTokenPair(poolAddress, token0Address, token0Address, 3000)
      ).to.be.revertedWithCustomError(tokenPairs, "TokenAddressesNotSorted");
    });
  });
});
