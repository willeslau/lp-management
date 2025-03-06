import { expect } from 'chai';
import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../scripts/util';

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ONE_ADDRESS = "0x0000000000000000000000000000000000000001";

describe('LiquiditySwapV3', () => {
    let swapCalculator: Contract;
    let quoter: Contract;
    let swapCalculatorSwapTester: Contract;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        // @ts-ignore
        quoter = await deployContractWithDeployer(deployer as Signer, 'UniswapV3QuoterTest', [], true);
        // @ts-ignore
        swapCalculator = await deployContractWithDeployer(deployer as Signer, 'LiquiditySwapV3', [await quoter.getAddress()], true);
        // @ts-ignore
        swapCalculatorSwapTester = await deployContractWithDeployer(deployer as Signer, 'UniswapV3LiquiditySwapTest', [await swapCalculator.getAddress()], true);
    });

    it('compute R correctly', async () => {
        const priceSqrtLow_Q96 = "4192360296907066341452660342784";
        const priceSqrtCur_Q96 = "4218481174524931107978693574656";
        const priceSqrtHig_Q96 = "4339505179874779672736325173248";

        const expectedR_Q96 = 49869267033240137919016702592389n;

        const R_Q96 = await swapCalculator.computeR(priceSqrtCur_Q96, priceSqrtLow_Q96, priceSqrtHig_Q96);
        expect(R_Q96).to.be.eq(expectedR_Q96);
    });

    it('swap token 1 for 0 works R correctly', async () => {
        const liquidity = "1409862032491040733326409";
        const pCurrent = "4551194197074107514614710272";
        await quoter.setParams(pCurrent, liquidity);

        // token 1 is eth, token 0 is uniswap
        await expect(
            swapCalculatorSwapTester.calSwapToken1ForToken0(
                {
                    poolFee: 0, // not important
                    token0: ZERO_ADDRESS,
                    token1: ONE_ADDRESS,
                    amount0: ethers.parseEther("1000"),
                    amount1: ethers.parseEther("20"),
                    sqrtP_Q96: "4551194197074107514614710272",
                    sqrtPSlippage_Q96: 0, // not important
                    R_Q96: "142246744265321288118042624"
                },
                {
                    swapInLow: ethers.parseEther("0"),
                    swapInHigh: ethers.parseEther("20"),
                    searchLoopNum: 20,
                    REpslon_Q96: "79228162514264339242811392",
                }
            )
        )
        .to.emit(swapCalculatorSwapTester, 'CalculatedTokenSwap').withArgs(3571515538282492507250n, 11787109375000000000n);
    });
});