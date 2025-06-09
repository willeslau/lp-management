import { Contract } from "ethers";
import { ethers } from "hardhat";
import { deployUpgradeableContract } from "../scripts/util";
import { expect } from "chai";

describe("UniswapV3LpManagerV3 - Util", () => {
  let contract: Contract;

  beforeEach(async () => {
    const [liquidityOwner, balancer, user] = await ethers.getSigners();

    contract = await deployUpgradeableContract(
      balancer,
      "UniswapV3LpManagerV3Test",
      [
        await liquidityOwner.getAddress(),
        await balancer.getAddress(),
      ],
      true
    );
  });

  it("floor tick works", async () => {
    let result = await contract.floorTick(-10, 3);
    expect(result).to.be.eq(-12);

    result = await contract.floorTick(-11, 3);
    expect(result).to.be.eq(-12);

    result = await contract.floorTick(-12, 3);
    expect(result).to.be.eq(-12);

    result = await contract.floorTick(10, 3);
    expect(result).to.be.eq(9);

    result = await contract.floorTick(9, 3);
    expect(result).to.be.eq(9);

    result = await contract.floorTick(8, 3);
    expect(result).to.be.eq(6);
  });

  it("ceil tick works", async () => {
    let result = await contract.ceilTick(-10, 3);
    expect(result).to.be.eq(-9);

    result = await contract.ceilTick(-12, 3);
    expect(result).to.be.eq(-12);

    result = await contract.ceilTick(10, 3);
    expect(result).to.be.eq(9);
  });

  it("skewed lower range works", async () => {
    let [r0, r1] = await contract.skewedLowerRange(-10, -4, 3);
    expect(r0).to.be.eq(-12);
    expect(r1).to.be.eq(-6);

    [r0, r1] = await contract.skewedLowerRange(-10, -4, 1);
    expect(r0).to.be.eq(-10);
    expect(r1).to.be.eq(-5);

    [r0, r1] = await contract.skewedLowerRange(-10, 5, 3);
    expect(r0).to.be.eq(-12);
    expect(r1).to.be.eq(3);

    [r0, r1] = await contract.skewedLowerRange(1, 20, 3);
    expect(r0).to.be.eq(0);
    expect(r1).to.be.eq(18);
  });

  it("skewed upper range works", async () => {
    let [r0, r1] = await contract.skewedUpperRange(-1, -4, 3);
    expect(r0).to.be.eq(-3);
    expect(r1).to.be.eq(0);

    [r0, r1] = await contract.skewedUpperRange(6, -10, 3);
    expect(r0).to.be.eq(-9);
    expect(r1).to.be.eq(6);

    [r0, r1] = await contract.skewedUpperRange(6, -3, 3);
    expect(r0).to.be.eq(0);
    expect(r1).to.be.eq(6);

    [r0, r1] = await contract.skewedUpperRange(-50, -60, 1);
    expect(r0).to.be.eq(-59);
    expect(r1).to.be.eq(-50);

    [r0, r1] = await contract.skewedUpperRange(80, 60, 1);
    expect(r0).to.be.eq(61);
    expect(r1).to.be.eq(80);
  });
});