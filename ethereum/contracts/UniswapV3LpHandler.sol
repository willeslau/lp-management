// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {IUniswapV3TokenPairs, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {LibPercentageMath} from "./RateMath.sol";

contract UniswapV3LpHandler is IERC721Receiver {
    using LibTokenId for uint8;
    using LibPercentageMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        uint8 tokenPair;
        /// @dev One can dynamically query the position of the deposit
        /// @dev but it saves slight gas if stored locally in this contract
        uint128 liquidity;
    }

    /// @notice The list of parameters for uniswap V3 liquidity operations
    struct OperationParams {
        /// @notice The max slippage allowed when providing liquidity
        uint16 maxMintSlippageRate;
    }

    error CallerNotPositionNFT(address caller);
    error DuplicatedPosition(uint256 tokenId);
    /// @dev This is a sanity check error. It means uniswap minted a token pair this contract does not support.
    error MintedUnsupportedTokenPair();
    error TokenPairIdNotSupported(uint8 tokenPairId);
    error NotLiquidityOwner(address sender);
    /// @dev This means current contract is not the owner of the position nft from uniswap 
    error PositionNFTNotReceived(uint256 tokenId);
    error NotOwningPositionNFT(uint256 tokenId);

    /// @notice The owner of liquidity. This address has the permission to close positions
    address liquidityOwner;
    /// @notice The address of the position nft from uniswap
    address positionNFTAddress;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public immutable supportedTokenPairs;

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    /// @dev The list of configuration parameters for liquidity operations
    OperationParams public params;

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        IUniswapV3TokenPairs _supportedTokenPairs,
        address _liquidityOwner,
        address _positionNFTAddress
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        supportedTokenPairs = _supportedTokenPairs;
        liquidityOwner = _liquidityOwner;
        positionNFTAddress = _positionNFTAddress;

        // max slippage is 3%
        params.maxMintSlippageRate = 30;
    }

    modifier onlyLiquidityOwner() {
        if (msg.sender != liquidityOwner) {
            revert NotLiquidityOwner(msg.sender);
        }

        _;
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (msg.sender != address(_positionNFTAddress)) {
            revert CallerNotPositionNFT(msg.sender);
        }

        // TODO: check owner if indeed address(this)

        _createDeposit(_tokenId);

        return this.onERC721Received.selector;
    }

    function _createDeposit(uint256 tokenId) internal {
        // sanity check
        if (deposits[tokenId].tokenPair.isValidTokenPairId()) {
            revert DuplicatedPosition(tokenId);
        }

        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        // sanity check
        uint8 tokenPairId = supportedTokenPairs.getTokenPairId(token0, token1);
        if (!tokenPairId.isValidTokenPairId()) {
            revert MintedUnsupportedTokenPair();
        }

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({
            tokenPair: tokenPairId,
            liquidity: liquidity
        });
    }

    /// @notice Mints a new position in uniswap LP pool. Only the liquidity owner can trigger this function.
    /// @param _tokenPairId The id of the token pair to mint in uniswap v3
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    /// @param tickLower The amount of token0
    /// @param amount1 The amount of token1
    function mintNewPosition(
        uint8 _tokenPairId, 
        uint256 _amount0, 
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(_tokenPairId);

        // ensure valida token pair
        if (!LibTokenId.isValidTokenPairId(tokenPair.id)) {
            revert TokenPairIdNotSupported(_tokenPairId);
        }
        
        _transferFundsAndApprove(tokenPair.token0, _amount0);
        _transferFundsAndApprove(tokenPair.token1, _amount1);
        
        uint16 maxMintSlippageRate = params.maxMintSlippageRate;

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: tokenPair.token0,
                token1: tokenPair.token1,
                fee: tokenPair.poolFee,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: _amount0,
                amount1Desired: _amount1,
                amount0Min: _amount0 - _amount0.multiply(maxMintSlippageRate),
                amount1Min: _amount1 - _amount1.multiply(maxMintSlippageRate),
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0Minted, amount1Minted) = nonfungiblePositionManager
            .mint(params);

        _refund(tokenPair.token0, _amount0, amount0Minted);
        _refund(tokenPair.token1, _amount1, amount1Minted);

        _ensureNFTReceived(tokenId);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param _tokenId The id of the erc721 token
    function collectAllFees(
        uint256 _tokenId
    ) external onlyLiquidityOwner {
        uint8 tokenPairId = _ensureOwningNFT(_tokenId);

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // now send collected fees back to owner
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(tokenPairId);
        
        // TODO: charge some fee for the protocol

        _sendTo(msg.sender, tokenPair.token0, amount0);
        _sendTo(msg.sender, tokenPair.token1, amount1);
    }

    /// @notice A function that decreases the current liquidity.
    /// @param _tokenId The id of the erc721 token
    function decreaseLiquidity(
        uint256 _tokenId,
        uint16 _percentage
    ) external onlyLiquidityOwner {
        require(msg.sender == deposits[tokenId].owner, "Not the owner");
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: halfLiquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    ) external onlyLiquidityOwner {
        TransferHelper.safeTransferFrom(
            deposits[tokenId].token0,
            msg.sender,
            address(this),
            amountAdd0
        );
        TransferHelper.safeTransferFrom(
            deposits[tokenId].token1,
            msg.sender,
            address(this),
            amountAdd1
        );

        TransferHelper.safeApprove(
            deposits[tokenId].token0,
            address(nonfungiblePositionManager),
            amountAdd0
        );
        TransferHelper.safeApprove(
            deposits[tokenId].token1,
            address(nonfungiblePositionManager),
            amountAdd1
        );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amountAdd0,
                    amount1Desired: amountAdd1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (liquidity, amount0, amount1) = nonfungiblePositionManager
            .increaseLiquidity(params);
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
        SafeERC20.safeTransfer(_tokenAddress, _recipient, _amount);
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferFundsAndApprove(
        address _tokenAddress,
        uint256 _amount
    ) intenral {
        // transfer tokens to contract
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve the position manager
        IERC20(_tokenAddress).safeApprove(
            address(nonfungiblePositionManager),
            _amount
        );
    }

    /// @dev Makes sure the expected nft position token is received at the end of a new mint operation
    function _ensureNFTReceived(uint256 _tokenId) internal {
        if (!deposits[_tokenId].tokenPair.isValidTokenPairId()) {
            revert PositionNFTNotReceived(_tokenId);
        }
    }

    /// @dev Ensures this contract own the token id
    function _ensureOwningNFT(uint256 _tokenId) internal returns (uint8) {
        uint8 tokenPairId = deposits[_tokenId];
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
    ) intenral {
        if (_amountExpected > _amountActual) {
            IERC20(_tokenAddress).safeApprove(address(nonfungiblePositionManager), 0);
            IERC20(_tokenAddress).safeTransfer(msg.sender, _amountExpected - _amountActual);
        }
    }
}
