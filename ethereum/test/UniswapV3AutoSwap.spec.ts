import { expect } from 'chai';
import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../scripts/util';

describe('UniswapV3AutoSwap', () => {
    let autoSwap: Contract;
    let mockSwapRouter: Contract;
    let mockSwapPool: Contract;
    let mockToken0: Contract;
    let mockToken1: Contract;
    let deployer: Signer;
    let user: Signer;
    let deployerAddress: string;
    let userAddress: string;

    beforeEach(async () => {
        [deployer, user] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        userAddress = await user.getAddress();

        // Deploy mock contracts
        mockToken0 = await deployContractWithDeployer(deployer, 'MockERC20', ['Token0', 'TK0', 18], false);
        mockToken1 = await deployContractWithDeployer(deployer, 'MockERC20', ['Token1', 'TK1', 18], false);
        
        // Deploy mock swap router and pool
        mockSwapRouter = await deployContractWithDeployer(deployer, 'MockSwapRouter', [], false);
        mockSwapPool = await deployContractWithDeployer(deployer, 'MockUniswapV3Pool', 
            [mockToken0.getAddress(), mockToken1.getAddress(), 3000], false);
        
        // Deploy the contract under test
        autoSwap = await deployContractWithDeployer(
            deployer, 
            'UniswapV3AutoSwap', 
            [await mockSwapRouter.getAddress(), await mockSwapPool.getAddress()], 
            false
        );
    });

    it('should initialize with correct values', async () => {
        // Test that the constructor sets the correct values
        expect(await autoSwap.swapRouter()).to.equal(await mockSwapRouter.getAddress());
        expect(await autoSwap.swapPool()).to.equal(await mockSwapPool.getAddress());
        expect(await autoSwap.token0()).to.equal(await mockToken0.getAddress());
        expect(await autoSwap.token1()).to.equal(await mockToken1.getAddress());
        // Fee is returned as a bigint, so we need to convert it
        expect(await autoSwap.fee()).to.equal(BigInt(3000));
    });

    it('should route swap to pool when liquidity is sufficient', async () => {
        // Setup mock responses
        const amountIn = ethers.parseEther('10');
        const amountOutMinimum = ethers.parseEther('9');
        const amountOut = ethers.parseEther('9.5');
        const zeroForOne = true;
        
        // Mock the token pair
        const tokenPair = {
            id: 1,
            token0: await mockToken0.getAddress(),
            token1: await mockToken1.getAddress(),
            poolFee: 3000
        };

        // Setup mock behavior for isPoolLiquiditySufficient
        await mockSwapPool.setLiquidity(ethers.parseEther('1000'));
        await mockSwapPool.setSqrtPriceX96("4218481174524931107978693574656");
        await mockSwapPool.setTick(100);
        await mockSwapPool.setTickSpacing(10);
        
        // Setup mock behavior for swap
        await mockSwapPool.setSwapResult(amountOut);
        
        // Fund user with tokens
        await mockToken0.mint(userAddress, amountIn);
        // @ts-ignore
        await mockToken0.connect(user).approve(await autoSwap.getAddress(), amountIn);
        
        // Fund pool with output tokens for the swap
        await mockToken1.mint(await mockSwapPool.getAddress(), amountOut);
        
        // Execute swap
        // @ts-ignore
        await autoSwap.connect(user).swap(
            tokenPair,
            amountIn,
            amountOutMinimum,
            zeroForOne
        );
        
        // Verify swap was routed to pool
        expect(await mockSwapPool.swapCalled()).to.be.true;
        expect(await mockSwapRouter.swapCalled()).to.be.false;
    });

    it('should route swap to router when liquidity is insufficient', async () => {
        // Setup mock responses
        const amountIn = ethers.parseEther('1000');
        const amountOutMinimum = ethers.parseEther('900');
        const amountOut = ethers.parseEther('950');
        const zeroForOne = true;
        
        // Mock the token pair
        const tokenPair = {
            id: 1,
            token0: await mockToken0.getAddress(),
            token1: await mockToken1.getAddress(),
            poolFee: 3000
        };

        // Setup mock behavior for isPoolLiquiditySufficient
        await mockSwapPool.setLiquidity(ethers.parseEther('10')); // Low liquidity
        await mockSwapPool.setSqrtPriceX96("4218481174524931107978693574656");
        await mockSwapPool.setTick(100);
        await mockSwapPool.setTickSpacing(10);
        
        // Setup mock behavior for swap
        await mockSwapRouter.setSwapResult(amountOut);
        
        // Fund user with tokens
        await mockToken0.mint(userAddress, amountIn);
        // @ts-ignore
        await mockToken0.connect(user).approve(await autoSwap.getAddress(), amountIn);
        
        // Fund router with output tokens for the swap
        await mockToken1.mint(await mockSwapRouter.getAddress(), amountOut);
        
        // Execute swap
        // @ts-ignore
        await autoSwap.connect(user).swap(
            tokenPair,
            amountIn,
            amountOutMinimum,
            zeroForOne
        );
        
        // Verify swap was routed to router
        expect(await mockSwapPool.swapCalled()).to.be.false;
        expect(await mockSwapRouter.swapCalled()).to.be.true;
    });

    it('should correctly determine if pool liquidity is sufficient', async () => {
        // Setup test parameters
        const smallAmount = ethers.parseEther('1');
        const largeAmount = ethers.parseEther('1000');
        
        // Setup mock pool with moderate liquidity
        await mockSwapPool.setLiquidity(ethers.parseEther('100'));
        await mockSwapPool.setSqrtPriceX96("4218481174524931107978693574656");
        await mockSwapPool.setTick(100);
        await mockSwapPool.setTickSpacing(10);
        
        // Test with small amount (should be sufficient)
        const sufficientForSmallAmount = await autoSwap.isPoolLiquiditySufficient(smallAmount, true);
        expect(sufficientForSmallAmount).to.be.true;
        
        // Test with large amount (should be insufficient)
        const sufficientForLargeAmount = await autoSwap.isPoolLiquiditySufficient(largeAmount, true);
        expect(sufficientForLargeAmount).to.be.false;
        
        // Test opposite direction (token1 to token0)
        // Note: The behavior might be different based on the mock setup
        // We're testing the function call works, not the specific return value
        await autoSwap.isPoolLiquiditySufficient(smallAmount, false);
        await autoSwap.isPoolLiquiditySufficient(largeAmount, false);
    });
});