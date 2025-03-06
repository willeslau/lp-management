import { expect } from 'chai';
import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../scripts/util';

describe('LiquiditySwapV3', () => {
    let swapCalculator: Contract;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();

        // @ts-ignore
        swapCalculator = await deployContractWithDeployer(deployer as Signer, 'LiquiditySwapV3', [], false);

    });

    it('compute R correctly', async () => {
        const priceSqrtLow_Q96 = "4192360296907066341452660342784";
        const priceSqrtCur_Q96 = "4218481174524931107978693574656";
        const priceSqrtHig_Q96 = "4339505179874779672736325173248";

        const expectedR_Q96 = 49869267033240137919016702592389n;

        const R_Q96 = await swapCalculator.computeR(priceSqrtCur_Q96, priceSqrtLow_Q96, priceSqrtHig_Q96);
        expect(R_Q96).to.be.eq(expectedR_Q96);
    });
});