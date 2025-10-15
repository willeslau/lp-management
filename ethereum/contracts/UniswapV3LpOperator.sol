// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPairAmount, LibTokenPairAmount} from "./libraries/LibTokenPairAmount.sol";

import {IRebalanceSwapMath, QuoteParams} from "./RebalanceSwapMath.sol";
import {ISwapUtil, SwapParams, Swapper} from "./SwapUtil.sol";

import {UniswapV3Operations, PoolMetadata} from "./UniswapV3Operations.sol";
import {RebalanceMath} from "./RebalanceMath.sol";

interface IPancakeMasterChef {
    function withdraw(uint256 _tokenId, address _to) external returns (uint256 reward);
}

contract UniswapV3LpOperator is RebalanceMath, UniswapV3Operations, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    error NoPosition();

    uint256 private tokenId;
    uint256 private openPositionAmount0;
    uint256 private openPositionAmount1;
    int24 private openPositionTick;

    address public pancakeMasterChef;

    struct OperatorPosition {
        Position position;
        uint256 openPositionAmount0;
        uint256 openPositionAmount1;
        int24 openPositionTick;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _manager,
        address _swapUtil,
        address _swapMath,
        address _pancakeMasterChef
    ) external initializer {
        __Ownable_init(msg.sender);
        manager = INonfungiblePositionManager(_manager);
        swapMath = IRebalanceSwapMath(_swapMath);
        swapUtil = ISwapUtil(_swapUtil);
        pancakeMasterChef = _pancakeMasterChef;

        tokenId = 0;
    }

    function getPosition() external view returns (OperatorPosition memory position) {
        if (tokenId == 0) revert NoPosition();
        position.position = _getPosition(tokenId);
        position.openPositionAmount0 = openPositionAmount0;
        position.openPositionAmount1 = openPositionAmount1;
    }

    function withdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner(), balance);
    }

    function withdraw(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function deriveTickRange(
        address _pool,
        uint160 _rangeUpperSqrt,
        uint160 _rangeLowerSqrt
    ) public view returns(int24, int24) {
        (uint160 priceSqrt, ) = _slot0(_pool);
        int24 tickSpacing = IUniswapV3Pool(_pool).tickSpacing();
        return _deriveTickRange(_rangeUpperSqrt, _rangeLowerSqrt, priceSqrt, tickSpacing);
    }

    function swapAndMint(
        QuoteParams calldata _quote,
        address _pool,
        PoolMetadata memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _deadline
    )
        external
        onlyOwner
    {
        _swapAndMint(_quote, _pool, _tokenPair, _tickLower, _tickUpper, _deadline);
    }

    function mint(
        PoolMetadata memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        TokenPairAmount memory _amounts,
        uint256 _deadline
    )
        external
        onlyOwner
    {
        (tokenId, , ) = _mint(_tokenPair, _tickLower, _tickUpper, _amounts, _deadline);

        IERC721(address(manager)).safeTransferFrom(address(this), pancakeMasterChef, tokenId);
    }

    function close(
        uint256 _deadline
    ) external onlyOwner returns (TokenPairAmount memory amounts) {
        if (tokenId == 0) revert NoPosition();

        IPancakeMasterChef(pancakeMasterChef).withdraw(tokenId, address(this));

        amounts = _close(tokenId, address(this), _deadline);

        tokenId = 0;
    }

    function _swapAndMint(
        QuoteParams calldata _quote,
        address _pool,
        PoolMetadata memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _deadline
    )
        internal
    {
        if (tokenId != 0) {
            _close(tokenId, address(this), _deadline);
        }

        TokenPairAmount memory amounts;
        amounts.amount0 = IERC20(_tokenPair.token0).balanceOf(address(this));
        amounts.amount1 = IERC20(_tokenPair.token1).balanceOf(address(this));

        TokenPairAmount memory principles = _swap(
            _quote,
            _pool,
            _tokenPair,
            amounts,
            _tickLower,
            _tickUpper
        );
        (tokenId, openPositionAmount0, openPositionAmount1) = _mint(_tokenPair, _tickLower, _tickUpper, principles, _deadline);
        (, openPositionTick) = _slot0(_pool);
    }

    function _slot0(
        address _pool
    ) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        // using low level call instead as we want to parse the data ourselves.
        // why do we do this? Because we want to support both uniswap and pancakeswap
        // uniswap.slot0.fee is uint8 but pancakeswap is u32
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "sf");

        (sqrtPriceX96, tick) = abi.decode(data, (uint160, int24));
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
