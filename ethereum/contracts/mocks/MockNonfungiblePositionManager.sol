// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

struct Position {
    uint96 nonce;
    address operator;
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
}

contract MockNonfungiblePositionManager is INonfungiblePositionManager, ERC721 {
    uint256 private _nextTokenId = 1;
    mapping(uint256 => Position) private _positions;
    
    uint256 private _mockCollectAmount0;
    uint256 private _mockCollectAmount1;
    
    uint256 private _mockDecreaseAmount0;
    uint256 private _mockDecreaseAmount1;

    constructor() ERC721("Mock Uniswap V3 Positions NFT-V1", "UNI-V3-POS") {}

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        tokenId = _nextTokenId++;
        liquidity = params.amount0Desired > 0 ? uint128(params.amount0Desired) : uint128(params.amount1Desired);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        _mint(params.recipient, tokenId);
        emit Transfer(address(0), params.recipient, tokenId);

        return (tokenId, liquidity, amount0, amount1);
    }

    function positions(
        uint256 tokenId
    )
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position storage position = _positions[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function burn(uint256 tokenId) external payable override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        delete _positions[tokenId];
        _burn(tokenId);
    }

    function collect(
        CollectParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1) {
        require(_isApprovedOrOwner(msg.sender, params.tokenId), "Not approved");
        amount0 = _mockCollectAmount0;
        amount1 = _mockCollectAmount1;
        Position storage position = _positions[params.tokenId];
        position.tokensOwed0 = 0;
        position.tokensOwed1 = 0;
        return (amount0, amount1);
    }

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1) {
        require(_isApprovedOrOwner(msg.sender, params.tokenId), "Not approved");
        Position storage position = _positions[params.tokenId];
        position.liquidity -= params.liquidity;
        amount0 = _mockDecreaseAmount0;
        amount1 = _mockDecreaseAmount1;
        return (amount0, amount1);
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        override
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(_exists(params.tokenId), "Token does not exist");
        Position storage position = _positions[params.tokenId];
        liquidity = uint128(params.amount0Desired + params.amount1Desired);
        position.liquidity = position.liquidity + liquidity;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        return (liquidity, amount0, amount1);
    }

    function positionSummary(
        uint256 tokenId
    )
        external
        view
        override
        returns (address token0, address token1, uint128 liquidity)
    {
        Position storage position = _positions[tokenId];
        require(_exists(tokenId), "Invalid position");
        return (position.token0, position.token1, position.liquidity);
    }
    
    function setPositionDetails(
        uint256 tokenId,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint24 fee
    ) external {
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        
        if (!_exists(tokenId)) {
            _mint(msg.sender, tokenId);
        }
    }

    function setCollectAmounts(uint256 amount0, uint256 amount1) external {
        _mockCollectAmount0 = amount0;
        _mockCollectAmount1 = amount1;
    }

    function setDecreaseAmounts(uint256 amount0, uint256 amount1) external {
        _mockDecreaseAmount0 = amount0;
        _mockDecreaseAmount1 = amount1;
    }
}