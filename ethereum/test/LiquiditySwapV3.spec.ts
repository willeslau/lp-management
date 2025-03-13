import { expect } from 'chai';
import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../scripts/util';

const REpslon = 0.001;

function ensureRWithinRange(R: number, RNew: number) {
    expect((RNew - R) / R).to.be.lte(REpslon);
}

describe('LiquiditySwapV3', () => {
    let swap: Contract;
    let pool: Contract;
    let token: Contract;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        // @ts-ignore
        pool = await deployContractWithDeployer(deployer as Signer, 'UniswapV3PoolTest', [], true);
        // @ts-ignore
        swap = await deployContractWithDeployer(deployer as Signer, 'LiquiditySwapV3', [], true);   
        // @ts-ignore
        token = await deployContractWithDeployer(deployer as Signer, 'TestToken', ["T", "T", deployer.address, ethers.parseEther("100000000000")], true)

        await token.approve(await swap.getAddress(), ethers.parseEther("100000000000"));
    });

    it('swap token 1 for 0 works R correctly', async () => {
        const liquidity = "1409862032491040733326409";
        const pCurrent = "4551194197074107514614710272";
        const R_Q96 = "142246744265321288118042624";
        await pool.setParams(pCurrent, liquidity);

        // token 1 is eth, token 0 is uniswap
        const zeroForOne = false;
        const amount0 = ethers.parseEther("1000");
        const amount1 = ethers.parseEther("20");

        const bytes = await swap.encodePreSwapData(
            zeroForOne,
            {
                amount0,
                amount1,
                R_Q96,
                tokenIn: await token.getAddress(),
            }
        );

        const amount0Expected = 3571515538282492507250n;
        const amount1Expected = -11787109375000000000n;
        const loopsExpected = 11;

        await expect(
            swap.swapWithSearch1For0(
                await pool.getAddress(),
                0, // not important
                {
                    swapInLow: ethers.parseEther("0"),
                    swapInHigh: ethers.parseEther("20"),
                    searchLoopNum: 20,
                },
                bytes,
            )
        )
        // need to reverse the sign as the pool expects sign to be reverse compared to caller
        .to.emit(swap, 'SwapOk').withArgs(-amount0Expected, -amount1Expected, loopsExpected);

        const newR = Number(amount1 + amount1Expected) / Number(amount0 + amount0Expected);
        ensureRWithinRange(Number(R_Q96) / 2 ** 96, newR);
    });

    it('swap token 0 for 1 works R correctly', async () => {
        const liquidity = "1440406078728975522569307";
        const pCurrent = "4550228513169945223468417024";
        const R_Q96 = "142246744265321288118042624";
        await pool.setParams(pCurrent, liquidity);

        // token 1 is eth, token 0 is uniswap
        const zeroForOne = true;
        const amount0 = ethers.parseEther("1000");
        const amount1 = ethers.parseEther("0.1");

        const bytes = await swap.encodePreSwapData(
            zeroForOne,
            {
                amount0,
                amount1,
                R_Q96,
                tokenIn: await token.getAddress(),
            }
        );

        const amount0Expected = -333007812499999999999n;
        const amount1Expected = 1098388313632070405n;
        const loopsExpected = 10;

        await expect(
            swap.swapWithSearch0For1(
                await pool.getAddress(),
                0, // not important
                {
                    swapInLow: ethers.parseEther("0"),
                    swapInHigh: ethers.parseEther("1000"),
                    searchLoopNum: 20,
                },
                bytes,
            )
        )
        // need to reverse the sign as the pool expects sign to be reverse compared to caller
        .to.emit(swap, 'SwapOk').withArgs(-amount0Expected, -amount1Expected, loopsExpected);

        const newR = Number(amount1 + amount1Expected) / Number(amount0 + amount0Expected);
        ensureRWithinRange(Number(R_Q96) / 2 ** 96, newR);
    });

    it('callback not allowed', async () => {
        const bytes = await swap.encodePreSwapData(
            true,
            {
                amount0: ethers.parseEther("1000"),
                amount1: ethers.parseEther("0.1"),
                R_Q96: "142246744265321288118042624",
                tokenIn: await token.getAddress(),
            }
        );

        await expect(
            swap.uniswapV3SwapCallback(
                ethers.parseEther("0"),
                ethers.parseEther("1"),
                bytes,
            )
        )
        .to.revertedWithCustomError(swap, 'NotExpectingCallback');
    });
});

describe('LiquiditySwapV3 - Revert Tests', () => {
    let contract: Contract;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        // @ts-ignore
        contract = await deployContractWithDeployer(deployer as Signer, 'RevertDataTesting', [], true);
    });

    it('ok', async () => {
        await contract.test_Postive();
        await contract.test_Negative();
        await contract.test_Zero();
        await contract.test_MaxPositive();
        await contract.test_MinNegative();
    });
});