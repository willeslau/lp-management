// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3TokenPairs, TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {INonfungiblePositionManager, MintParams, IncreaseLiquidityParams, CollectParams, DecreaseLiquidityParams} from "./interfaces/INonfungiblePositionManager.sol";
import {LibPercentageMath} from "./RateMath.sol";
import {ISwapHandler} from "./interfaces/ISwapHandler.sol";

/// @notice Represents the deposit of an NFT
struct Deposit {
    uint8 tokenPair;
    /// @notice One can dynamically query the position of the deposit
    /// @notice but it saves slight gas if stored locally in this contract
    uint128 liquidity;
    /// @notice The total fee collected
    uint256 fee0;
    uint256 fee1;
}

/// @notice The list of parameters for uniswap V3 liquidity operations
struct OperationParams {
    /// @notice True means the fee collected will be used into new position
    bool isCompoundFee;
    /// @notice The max slippage allowed when providing liquidity
    uint16 maxMintSlippageRate;
    /// @notice The protocol fee rate, base 1000 (e.g., 50 means 5%)
    uint16 protocolFeeRate;
}

struct RebalanceParams {
    uint8 tokenId;
    /// @dev for withdraw liquidity slippage protection
    uint256 amount0WithdrawMin;
    uint256 amount1WithdrawMin;
    uint16 swapSlippage;
    /// @dev new amounts to provide to the LP pool
    uint256 newAmount0;
    uint256 newAmount1;
    /// @dev new price range
    int24 tickLower;
    int24 tickUpper;
}

contract UniswapV3LpHandler is IERC721Receiver, IUniswapV3SwapCallback {
    using LibTokenId for uint8;
    using SafeERC20 for IERC20;

    error CallerNotPositionNFT(address caller);
    error DuplicatedPosition(uint256 tokenId);
    /// @dev This is a sanity check error. It means uniswap minted a token pair this contract does not support.
    error MintedUnsupportedTokenPair();
    error TokenPairIdNotSupported(uint8 tokenPairId);
    error NotLiquidityOwner(address sender);
    error NotBalancer(address sender);
    /// @dev This means current contract is not the owner of the position nft from uniswap
    error PositionNFTNotReceived(uint256 tokenId);
    /// @dev This means the current contract does not hold the position nft from uniswap
    event PositionCreated(
        uint256 indexed tokenId,
        uint8 tokenPair,
        uint128 liquidity
    );
    event PositionModified(uint256 indexed tokenId, uint128 newLiquidity);
    event FeesCollected(uint256 indexed tokenId, uint256 fee0, uint256 fee1);
    event PositionRebalanced(
        uint256 indexed tokenId,
        int24 tickLower,
        int24 tickUpper
    );
    error NotOwningPositionNFT(uint256 tokenId);
    error NotSwapable(
        uint256 reserve0,
        uint256 reserve1,
        uint256 target0,
        uint256 target1
    );
    error InvalidAddress();
    error RateTooHigh(uint16 rate);
    error InvalidTickRange(int24 tickLower, int24 tickUpper);
    error InvalidPool();
    error PoolNotExist();
    error InsufficientOutputAmount();
    error UnsupportedTokenPair();

    /// @notice The owner of liquidity. This address has the permission to close positions
    address liquidityOwner;
    /// @notice The address of the position nft from uniswap
    address positionNFTAddress;
    /// @notice The address that can rebalance the liquidity positions
    address balancer;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public immutable supportedTokenPairs;
    address public immutable swap;

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    /// @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        IUniswapV3TokenPairs _supportedTokenPairs,
        address _liquidityOwner,
        address _balancer,
        address _positionNFTAddress,
        address _swap
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        supportedTokenPairs = _supportedTokenPairs;
        liquidityOwner = _liquidityOwner;
        positionNFTAddress = _positionNFTAddress;
        balancer = _balancer;
        swap = _swap;

        // max slippage is 3%
        operationalParams.maxMintSlippageRate = 30;
        operationalParams.isCompoundFee = true;
        operationalParams.protocolFeeRate = 50;
    }

    modifier onlyLiquidityOwner() {
        if (msg.sender != liquidityOwner) {
            revert NotLiquidityOwner(msg.sender);
        }
        _;
    }

    modifier onlyBalancer() {
        if (msg.sender != balancer) {
            revert NotBalancer(msg.sender);
        }
        _;
    }

    function setLiquidityOwner(address _newOwner) external onlyLiquidityOwner {
        if (_newOwner == address(0)) {
            revert InvalidAddress();
        }
        liquidityOwner = _newOwner;
    }

    function setBalancer(address _newBalancer) external onlyLiquidityOwner {
        if (_newBalancer == address(0)) {
            revert InvalidAddress();
        }
        balancer = _newBalancer;
    }

    function setProtocolFeeRate(uint16 _newRate) external onlyLiquidityOwner {
        if (_newRate > 1000) {
            revert RateTooHigh(_newRate);
        }
        operationalParams.protocolFeeRate = _newRate;
    }

    function setMaxMintSlippageRate(uint16 newRate) external onlyBalancer {
        if (newRate > 1000) {
            revert RateTooHigh(newRate);
        }
        operationalParams.maxMintSlippageRate = newRate;
    }

    function setCompoundFee(bool compound) external onlyLiquidityOwner {
        operationalParams.isCompoundFee = compound;
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (msg.sender != address(positionNFTAddress)) {
            revert CallerNotPositionNFT(msg.sender);
        }

        // TODO: check owner if indeed address(this)

        _createDeposit(_tokenId);

        return this.onERC721Received.selector;
    }

    function rebalance(RebalanceParams calldata _params) external onlyBalancer {
        // First validate tick range
        _validateTickRange(_params.tickLower, _params.tickUpper);

        uint256 amount0;
        uint256 amount1;
        uint8 tokenPairId;

        {
            uint256 fee0;
            uint256 fee1;
            (fee0, fee1, tokenPairId) = _collectAllFees(_params.tokenId);

            (amount0, amount1, ) = _decreaseLiquidity(
                _params.tokenId,
                LibPercentageMath.percentage100(),
                _params.amount0WithdrawMin,
                _params.amount1WithdrawMin
            );

            if (operationalParams.isCompoundFee) {
                amount0 += fee0;
                amount1 += fee1;
            }
        }

        // currently all the collected fees and tokens are held by this contract

        // this step is tricky and loss can happen
        _trySwap(
            tokenPairId,
            amount0,
            amount1,
            _params.newAmount0,
            _params.newAmount1,
            _params.swapSlippage
        );

        // now we should have all the tokens, perform open position
        _mintNewPosition(
            tokenPairId,
            _params.newAmount0,
            _params.newAmount1,
            _params.tickLower,
            _params.tickUpper
        );

        emit PositionRebalanced(
            _params.tokenId,
            _params.tickLower,
            _params.tickUpper
        );
    }

    /// @notice Mints a new position in uniswap LP pool. Only the liquidity owner can trigger this function.
    /// @param _tokenPairId The id of the token pair to mint in uniswap v3
    /// @param _amount0 The amount of token0
    /// @param _amount1 The amount of token1
    /// @param _tickLower The lower price range
    /// @param _tickUpper The upper price range
    function mintNewPosition(
        uint8 _tokenPairId,
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) external onlyLiquidityOwner {
        _mintNewPosition(
            _tokenPairId,
            _amount0,
            _amount1,
            _tickLower,
            _tickUpper
        );
    }

    /// @notice Collects all the fees associated with provided liquidity
    /// @param tokenIds The id of the token pair to mint in uniswap v3
    function batchCollectFees(
        uint256[] calldata tokenIds
    ) external onlyLiquidityOwner {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            collectAllFees(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param _tokenId The id of the erc721 token
    function collectAllFees(uint256 _tokenId) public onlyLiquidityOwner {
        (uint256 amount0, uint256 amount1, uint8 tokenPairId) = _collectAllFees(
            _tokenId
        );

        // now send collected fees back to owner
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            tokenPairId
        );

        uint256 protocolFee0 = (amount0 * operationalParams.protocolFeeRate) /
            1000;
        uint256 protocolFee1 = (amount1 * operationalParams.protocolFeeRate) /
            1000;

        if (protocolFee0 != 0) {
            _sendTo(liquidityOwner, tokenPair.token0, protocolFee0);
        }

        if (protocolFee1 != 0) {
            _sendTo(liquidityOwner, tokenPair.token1, protocolFee1);
        }

        // TODO: charge some fee for the protocol
        _sendTo(msg.sender, tokenPair.token0, amount0 - protocolFee0);
        _sendTo(msg.sender, tokenPair.token1, amount1 - protocolFee1);

        emit FeesCollected(_tokenId, amount0, amount1);
    }

    /// @notice A function that decreases the current liquidity by the target percentage.
    function decreaseLiquidity(
        uint256 _tokenId,
        uint16 _percentage,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        (
            uint256 amount0,
            uint256 amount1,
            uint8 tokenPairId
        ) = _decreaseLiquidity(_tokenId, _percentage, _amount0Min, _amount1Min);

        (address token0, address token1) = supportedTokenPairs
            .getTokenPairAddresses(tokenPairId);
        _sendTo(msg.sender, token0, amount0);
        _sendTo(msg.sender, token1, amount1);
        emit PositionModified(_tokenId, deposits[_tokenId].liquidity);
    }

    /// @notice Increases liquidity in the range of the nft
    /// @dev Pool must be initialized already to add liquidity
    function increaseLiquidity(
        uint256 _tokenId,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    ) external onlyLiquidityOwner {
        _increaseLiquidity(_tokenId, _amountAdd0, _amountAdd1);
        emit PositionModified(_tokenId, deposits[_tokenId].liquidity);
    }

    function _trySwap(
        uint8 _tokenPairId,
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _target0,
        uint256 _target1,
        uint16 _slippage
    ) internal {
        uint256 amountOutMinimum;
        uint256 amountIn;
        bool isToken0ToToken1;

        if (_reserve0 > _target0 && _reserve1 < _target1) {
            amountIn = _reserve0 - _target0;
            amountOutMinimum =
                ((_target1 - _reserve1) * (1000 - _slippage)) /
                1000;
            isToken0ToToken1 = true;
        } else if (_reserve0 < _target0 && _reserve1 > _target1) {
            amountIn = _reserve1 - _target1;
            amountOutMinimum =
                ((_target0 - _reserve0) * (1000 - _slippage)) /
                1000;
            isToken0ToToken1 = false;
        } else {
            revert NotSwapable(_reserve0, _reserve1, _target0, _target1);
        }

        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            _tokenPairId
        );
        _performSwap(tokenPair, amountIn, amountOutMinimum, isToken0ToToken1);
    }

    function _performSwap(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) internal {
        address tokenIn = isToken0ToToken1 ? tokenPair.token0 : tokenPair.token1;
        IERC20(tokenIn).safeIncreaseAllowance(swap, amountIn);
        _swapByPool(
            tokenPair,
            amountIn,
            amountOutMinimum,
            isToken0ToToken1
        );
    }

    /// @notice Swap tokens directly using UniswapV3Pool
    /// @param tokenPair Token pair information
    /// @param amountIn Input token amount
    /// @param amountOutMinimum Minimum output token amount
    /// @param isToken0ToToken1 Swap direction
    /// @return amountOut Actual output token amount
    function _swapByPool(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) internal returns (uint256 amountOut) {
        address tokenIn = isToken0ToToken1
            ? tokenPair.token0
            : tokenPair.token1;
        address tokenOut = isToken0ToToken1
            ? tokenPair.token1
            : tokenPair.token0;

        address pool = IUniswapV3Factory(swap).getPool(
            tokenPair.token0,
            tokenPair.token1,
            tokenPair.poolFee
        );
        if (pool == address(0)) {
            revert PoolNotExist();
        }

        _approveIfNeeded(tokenIn, pool, amountIn);

        uint160 sqrtPriceLimitX96 = 0;

        bytes memory callbackData = abi.encode(
            tokenIn,
            tokenOut,
            tokenPair.poolFee
        );

        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            isToken0ToToken1,
            int256(amountIn),
            sqrtPriceLimitX96,
            callbackData
        );

        amountOut = uint256(-(isToken0ToToken1 ? amount1 : amount0));
        if (amountOut < amountOutMinimum) {
            revert InsufficientOutputAmount();
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        (address tokenIn, address tokenOut, uint24 poolFee) = abi.decode(
            data,
            (address, address, uint24)
        );

        address pool = IUniswapV3Factory(swap).getPool(tokenIn, tokenOut, poolFee);
        if (msg.sender != pool) {
            revert InvalidPool();
        }
        
        uint8 tokenPairId = supportedTokenPairs.getTokenPairId(tokenIn, tokenOut);
        if (!supportedTokenPairs.isSupportTokenPair(tokenPairId)) {
            revert UnsupportedTokenPair();
        }
    }

    function _collectAllFees(
        uint256 _tokenId
    ) internal returns (uint256 amount0, uint256 amount1, uint8 tokenPairId) {
        tokenPairId = _ensureOwningNFT(_tokenId);

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        CollectParams memory collectParams = CollectParams({
            tokenId: _tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(collectParams);

        Deposit storage deposit = deposits[_tokenId];
        deposit.fee0 += amount0;
        deposit.fee1 += amount1;
    }

    function _createDeposit(uint256 _tokenId) internal {
        // sanity check
        if (deposits[_tokenId].tokenPair.isValidTokenPairId()) {
            revert DuplicatedPosition(_tokenId);
        }

        (
            address token0,
            address token1,
            uint128 liquidity
        ) = nonfungiblePositionManager.positionSummary(_tokenId);
        if (token0 == address(0) || token1 == address(0)) {
            revert PositionNFTNotReceived(_tokenId);
        }

        // sanity check
        uint8 tokenPairId = supportedTokenPairs.getTokenPairId(token0, token1);
        if (!tokenPairId.isValidTokenPairId()) {
            revert MintedUnsupportedTokenPair();
        }

        // set the owner and data for position
        // operator is msg.sender
        deposits[_tokenId] = Deposit({
            tokenPair: tokenPairId,
            liquidity: liquidity,
            fee0: 0,
            fee1: 0
        });
    }

    function _validateTickRange(
        int24 _tickLower,
        int24 _tickUpper
    ) internal pure {
        if (_tickLower >= _tickUpper) {
            revert InvalidTickRange(_tickLower, _tickUpper);
        }
    }

    function _mintNewPosition(
        uint8 _tokenPairId,
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) internal {
        _validateTickRange(_tickLower, _tickUpper);
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            _tokenPairId
        );

        // ensure valida token pair
        if (!LibTokenId.isValidTokenPairId(tokenPair.id)) {
            revert TokenPairIdNotSupported(_tokenPairId);
        }

        _transferFundsAndApprove(tokenPair.token0, _amount0);
        _transferFundsAndApprove(tokenPair.token1, _amount1);

        uint16 maxMintSlippageRate = operationalParams.maxMintSlippageRate;

        MintParams memory mintParams = MintParams({
            token0: tokenPair.token0,
            token1: tokenPair.token1,
            fee: tokenPair.poolFee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0,
            amount1Desired: _amount1,
            amount0Min: _amount0 -
                LibPercentageMath.multiply(_amount0, maxMintSlippageRate),
            amount1Min: _amount1 -
                LibPercentageMath.multiply(_amount1, maxMintSlippageRate),
            recipient: address(this),
            deadline: block.timestamp
        });

        (
            uint256 tokenId,
            ,
            uint256 amount0Minted,
            uint256 amount1Minted
        ) = nonfungiblePositionManager.mint(mintParams);

        _refund(tokenPair.token0, _amount0, amount0Minted);
        _refund(tokenPair.token1, _amount1, amount1Minted);

        // Create deposit record before checking NFT ownership
        deposits[tokenId] = Deposit({
            tokenPair: _tokenPairId,
            liquidity: 0,
            fee0: 0,
            fee1: 0
        });

        _ensureNFTReceived(tokenId);

        (, , uint128 liquidity) = nonfungiblePositionManager.positionSummary(
            tokenId
        );
        deposits[tokenId].liquidity = liquidity;
        emit PositionCreated(tokenId, _tokenPairId, liquidity);
    }

    function _increaseLiquidity(
        uint256 _tokenId,
        uint256 _amountAdd0,
        uint256 _amountAdd1
    ) internal {
        uint8 tokenPairId = _ensureOwningNFT(_tokenId);
        (address token0, address token1) = supportedTokenPairs
            .getTokenPairAddresses(tokenPairId);

        _transferFundsAndApprove(token0, _amountAdd0);
        _transferFundsAndApprove(token1, _amountAdd1);

        uint16 maxMintSlippageRate = operationalParams.maxMintSlippageRate;

        IncreaseLiquidityParams
            memory increaseParams = IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: _amountAdd0,
                amount1Desired: _amountAdd1,
                amount0Min: _amountAdd0 -
                    LibPercentageMath.multiply(
                        _amountAdd0,
                        maxMintSlippageRate
                    ),
                amount1Min: _amountAdd1 -
                    LibPercentageMath.multiply(
                        _amountAdd1,
                        maxMintSlippageRate
                    ),
                deadline: block.timestamp
            });

        (
            uint128 liquidity,
            uint256 amount0Minted,
            uint256 amount1Minted
        ) = nonfungiblePositionManager.increaseLiquidity(increaseParams);

        _refund(token0, _amountAdd0, amount0Minted);
        _refund(token1, _amountAdd1, amount1Minted);

        _updateNFTLiquidity(_tokenId, liquidity);
    }

    function _decreaseLiquidity(
        uint256 _tokenId,
        uint16 _percentage,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (uint256 amount0, uint256 amount1, uint8 tokenPairId) {
        tokenPairId = _ensureOwningNFT(_tokenId);

        if (_percentage > 1000) {
            revert RateTooHigh(_percentage);
        }
        uint128 newLiquidity = LibPercentageMath.multiplyU128(
            deposits[_tokenId].liquidity,
            _percentage
        );

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        DecreaseLiquidityParams
            memory decreaseParams = DecreaseLiquidityParams({
                tokenId: _tokenId,
                liquidity: newLiquidity,
                amount0Min: _amount0Min,
                amount1Min: _amount1Min,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            decreaseParams
        );

        (, , newLiquidity) = nonfungiblePositionManager.positionSummary(
            _tokenId
        );

        if (newLiquidity == 0) {
            delete deposits[_tokenId];
        } else {
            _updateNFTLiquidity(_tokenId, newLiquidity);
        }
    }

    function _updateNFTLiquidity(uint256 _tokenId, uint128 _addLiquidity) internal {
        deposits[_tokenId].liquidity += _addLiquidity;
    }

    /// @notice Transfers funds to owner of NFT
    /// @param _recipient The recipient of the funds
    /// @param _tokenAddress The address of the token to send
    /// @param _amount The amount of token
    function _sendTo(
        address _recipient,
        address _tokenAddress,
        uint256 _amount
    ) internal {
        IERC20(_tokenAddress).safeTransfer(_recipient, _amount);
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferFundsAndApprove(
        address _tokenAddress,
        uint256 _amount
    ) internal {
        // transfer tokens to contract
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve the position manager
        IERC20(_tokenAddress).forceApprove(
            address(nonfungiblePositionManager),
            _amount
        );
    }

    /// @dev Makes sure the expected nft position token is received at the end of a new mint operation
    function _ensureNFTReceived(uint256 _tokenId) internal view {
        if (!deposits[_tokenId].tokenPair.isValidTokenPairId()) {
            revert PositionNFTNotReceived(_tokenId);
        }
    }

    /// @dev Ensures this contract own the token id
    function _ensureOwningNFT(uint256 _tokenId) internal view returns (uint8) {
        uint8 tokenPairId = deposits[_tokenId].tokenPair;
        if (!tokenPairId.isValidTokenPairId()) {
            revert NotOwningPositionNFT(_tokenId);
        }
        return tokenPairId;
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _tokenAddress,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        if (_amountExpected > _amountActual) {
            IERC20(_tokenAddress).forceApprove(
                address(nonfungiblePositionManager),
                0
            );
            IERC20(_tokenAddress).safeTransfer(
                msg.sender,
                _amountExpected - _amountActual
            );
        }
    }

    function _approveIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, amount);
        }
    }
}
