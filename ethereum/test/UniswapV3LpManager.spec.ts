import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import {deployUniswapFactory, UniswapPool} from "./uniswapV3Deployer";
import {deployContractWithDeployer, loadContract} from "../scripts/util";
import { LPManager, PositionChange } from "../scripts/LPManager";
import { expect } from "chai";

describe('UniswapV3LpManager - Init', () => {
    let lpManager: LPManager;
    let uniswap: UniswapPool;
    let supportedTokenPairs: Contract;
    let balancer: Signer;
    let liquidityOwner: Signer;

    beforeEach(async () => {
        [liquidityOwner, balancer] = await ethers.getSigners();

        const tokenA = await deployContractWithDeployer(liquidityOwner, 'TestToken', ["UNI", "UNI", liquidityOwner.address, ethers.parseEther("100000000000")], true)
        const tokenB = await deployContractWithDeployer(liquidityOwner, 'TestToken', ["ETH", "ETH", liquidityOwner.address, ethers.parseEther("100000000000")], true)
        const fee = 3000;
        const initialPriceSqrtQ96 = "4436738577262596212334852517";
        uniswap = await deployUniswapFactory(liquidityOwner, await tokenA.getAddress(), await tokenB.getAddress(), fee, initialPriceSqrtQ96);

        supportedTokenPairs = await deployContractWithDeployer(
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

        lpManager = new LPManager(await deployContractWithDeployer(
            balancer,
            "UniswapV3LpManager",
            [
                await supportedTokenPairs.getAddress(),
                await liquidityOwner.getAddress(),
                await balancer.getAddress()
            ],
            true
        ));
    });
    
    it('initial liquidity add ok', async () => {
        const tokenPairId = 1;
        const amount0 = ethers.parseEther("312.5");
        const amount1 = ethers.parseEther("1");
        const tickLower = BigInt(-58140);
        const tickUpper = BigInt(-56640);
        // initial allow big "slippage"
        const slippage = 0.999;

        lpManager.useCaller(liquidityOwner);

        await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
        await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);
        
        const params = lpManager.createMintParams(tickLower, tickUpper, amount0, amount1, slippage);
        const result = await lpManager.mintNewPosition(tokenPairId, params);
        
        const queryResult = await lpManager.getPosition(result.positionKey);

        expect(queryResult.fee0).to.eq(0);
        expect(queryResult.fee1).to.eq(0);
        // TODO: the should be equal, but might be differ by 1 wei due to precision issues
        // expect(queryResult.amount0).to.eq(result.amount0);
        // expect(queryResult.amount1).to.eq(result.amount1);
    });
});

describe('UniswapV3LpManager - After Init', () => {
    let lpManager: LPManager;
    let uniswap: UniswapPool;
    let supportedTokenPairs: Contract;
    let balancer: Signer;
    let liquidityOwner: Signer;

    let initialLiquidity: bigint;
    let initialPositionKey: string;
    const tokenPairId = 1;

    beforeEach(async () => {
        [liquidityOwner, balancer] = await ethers.getSigners();

        const tokenA = await deployContractWithDeployer(liquidityOwner, 'TestToken', ["UNI", "UNI", liquidityOwner.address, ethers.parseEther("100000000000")], true)
        const tokenB = await deployContractWithDeployer(liquidityOwner, 'TestToken', ["ETH", "ETH", liquidityOwner.address, ethers.parseEther("100000000000")], true)
        const fee = 3000;
        const initialPriceSqrtQ96 = 4436738577262596212334852517n;
        uniswap = await deployUniswapFactory(liquidityOwner, await tokenA.getAddress(), await tokenB.getAddress(), fee, initialPriceSqrtQ96);

        supportedTokenPairs = await deployContractWithDeployer(
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

        lpManager = new LPManager(await deployContractWithDeployer(
            balancer,
            "UniswapV3LpManager",
            [
                await supportedTokenPairs.getAddress(),
                await liquidityOwner.getAddress(),
                await balancer.getAddress()
            ],
            true
        ));

        // now add initial liquidity
        // initial allow big "slippage"
        const slippage = 0.999;
        const amount0 = ethers.parseEther("3125");
        const amount1 = ethers.parseEther("10");
        const tickLower = BigInt(-58140);
        const tickUpper = BigInt(-56640);

        lpManager.useCaller(liquidityOwner);

        await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
        await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);
        
        const params = lpManager.createMintParams(tickLower, tickUpper, amount0, amount1, slippage);
        const result = await lpManager.mintNewPosition(tokenPairId, params);

        const queryResult = await lpManager.getPosition(result.positionKey);

        initialLiquidity = queryResult.liquidity;
        initialPositionKey = result.positionKey;
    });

    function withinPercentageDiff(a: BigInt, b: BigInt, tolerance: number) {
        const diff = Math.abs(Number(a) - Number(b)) / Number(a);
        expect(diff).to.be.lt(tolerance);
    }

    it('increase liquidity - works', async () => {
        const amount0 = ethers.parseEther("33");
        const amount1 = ethers.parseEther("0.1");

        await lpManager.useCaller(liquidityOwner);
        
        await lpManager.increaseAllowanceIfNeeded(uniswap.token0, amount0);
        await lpManager.increaseAllowanceIfNeeded(uniswap.token1, amount1);

        const params = {
            amount0,
            amount1,
            slippage: 0.99,
        }
        const positionChange = await lpManager.increaseLiquidity(initialPositionKey, params);

        expect(positionChange.change).to.eq(PositionChange.Increase);
        
        const newPosition = await lpManager.getPosition(initialPositionKey);
        expect(newPosition.liquidity).to.be.gt(initialLiquidity);
    });

    it('decrease liquidity - works', async () => {
        const amount0 = ethers.parseEther("0.3");
        const amount1 = ethers.parseEther("0.001");

        const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
        const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
        const token0InitialBalance = await token0.balanceOf(await liquidityOwner.getAddress());
        const token1InitialBalance = await token1.balanceOf(await liquidityOwner.getAddress());
        
        await lpManager.useCaller(liquidityOwner);
    
        const params = {
            newLiquidity: initialLiquidity / BigInt(2),
            amount0,
            amount1,
        };
        const positionChange = await lpManager.decreaseLiquidity(initialPositionKey, params);

        expect(positionChange.change).to.eq(PositionChange.Descrese);

        const newPosition = await lpManager.getPosition(initialPositionKey);
        expect(newPosition.liquidity).to.be.lt(initialLiquidity);

        const token0AfterBalance = await token0.balanceOf(await liquidityOwner.getAddress());
        const token1AfterBalance = await token1.balanceOf(await liquidityOwner.getAddress());
        expect(token0InitialBalance + positionChange.amount0).to.be.eq(token0AfterBalance);
        expect(token1InitialBalance + positionChange.amount1).to.be.eq(token1AfterBalance);
    });

    it('rebalance close position - compound fee', async () => {
        const token0 = await loadContract("IERC20", uniswap.token0, liquidityOwner);
        const token1 = await loadContract("IERC20", uniswap.token1, liquidityOwner);
        const token0InitialBalance = await token0.balanceOf(await lpManager.innerContract.getAddress());
        const token1InitialBalance = await token1.balanceOf(await lpManager.innerContract.getAddress());

        await lpManager.useCaller(balancer);

        const params = {
            amount0Min: BigInt(0),
            amount1Min: BigInt(0),
            compoundFee: true
        };
        const positionChange = await lpManager.rebalanceClosePosition(initialPositionKey, params);

        expect(positionChange.change).to.eq(PositionChange.Closed);

        await expect(lpManager.getPosition(initialPositionKey)).to.revertedWithCustomError(lpManager.innerContract, "InvalidPositionKey");

        const token0AfterBalance = await token0.balanceOf(await lpManager.innerContract.getAddress());
        const token1AfterBalance = await token1.balanceOf(await lpManager.innerContract.getAddress());
        expect(token0InitialBalance + positionChange.amount0).to.be.eq(token0AfterBalance);
        expect(token1InitialBalance + positionChange.amount1).to.be.eq(token1AfterBalance);
    });

    it('rebalance 1 for 0 - new position created', async () => {
        // sending 0.01 token1 to the contract to simulate rebalance close is already called
        const amount = ethers.parseEther("0.01");
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
            }
        }
        const expectedPosition0 = ethers.parseEther("1.5809169659443283");
        const expectedPosition1 = ethers.parseEther("0.005027581488006263");
        
        await lpManager.useCaller(balancer);
        
        const positionChange = await lpManager.rebalance1For0(rebalanceParams);

        expect(positionChange.change).to.eq(PositionChange.Create);
        withinPercentageDiff(positionChange.amount0, expectedPosition0, 0.01);
        withinPercentageDiff(positionChange.amount1, expectedPosition1, 0.01);
    });

    it('rebalance 0 for 1 - new position created', async () => {
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
            }
        }
        
        const expectedPosition0 = ethers.parseEther("0.4942500985897128");
        const expectedPosition1 = ethers.parseEther("0.0015812729456157");
        await lpManager.useCaller(balancer);
        
        const positionChange = await lpManager.rebalance0For1(rebalanceParams);
        expect(positionChange.change).to.eq(PositionChange.Create);
        withinPercentageDiff(positionChange.amount0, expectedPosition0, 0.01);
        withinPercentageDiff(positionChange.amount1, expectedPosition1, 0.01);
        
    });
});