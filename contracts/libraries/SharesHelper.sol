 // SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/Position.sol';
import '@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol';
import '@uniswap/v3-core/contracts/libraries/LiquidityMath.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

import "./CHI.sol";
import "./PoolPosition.sol";
import "../interfaces/ICHIVault.sol";
import "../interfaces/IYangNFTVault.sol";


library SharesHelper {
    function calcSharesAndAmounts(
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 totalSupply
    )
        internal
        pure
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        uint256 total0 = totalAmount0;
        uint256 total1 = totalAmount1;

        assert(totalSupply == 0 || total0 > 0 || total1 > 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = Math.max(amount0, amount1);
        } else if (total0 == 0) {
            amount1 = amount1Desired;
            shares = FullMath.mulDiv(amount1, totalSupply, total1);
        } else if (total1 == 0) {
            amount0 = amount0Desired;
            shares = FullMath.mulDiv(amount0, totalSupply, total0);
        } else {
            uint256 cross = Math.min(
                                SafeMath.mul(amount0Desired, total1),
                                SafeMath.mul(amount1Desired, total0)
                            );
            require(cross > 0, "c");

            // Round up amounts
            amount0 = SafeMath.add(SafeMath.div(SafeMath.sub(cross, 1), total1), 1);
            amount1 = SafeMath.add(SafeMath.div(SafeMath.sub(cross, 1), total0), 1);
            shares = SafeMath.div(FullMath.mulDiv(cross, totalSupply, total0), total1);
        }
    }

    function calcAmountsFromShares(
        IUniswapV3Pool pool,
        ICHIVault vault,
        address yang,
        uint256 yangId,
        uint256 shares
    )
        internal
        view
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        for (uint i = 0; i < vault.getRangeCount(); i++) {
            (int24 tickLower, int24 tickUpper) = vault.getRange(i);
            uint128 liquidity = _positionLiquidity(pool, address(vault), tickLower, tickUpper);
            if (liquidity > 0) {
                (uint256 _amount0, uint256 _amount1) = _burnLiquidityShare(
                                                            pool,
                                                            vault,
                                                            yang,
                                                            yangId,
                                                            liquidity,
                                                            shares,
                                                            tickLower,
                                                            tickUpper
                                                        );
                amount0 = SafeMath.add(amount0, _amount0);
                amount1 = SafeMath.add(amount1, _amount1);
            }
        }
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());
        uint256 unusedAmount0 = FullMath.mulDiv(
                    SafeMath.sub(token0.balanceOf(address(vault)), vault.accruedProtocolFees0()),
                    shares,
                    vault.totalSupply()
                );
        uint256 unusedAmount1 = FullMath.mulDiv(
                    SafeMath.sub(token1.balanceOf(address(vault)), vault.accruedProtocolFees1()),
                    shares,
                    vault.totalSupply()
                );
        amount0 = SafeMath.add(amount0, unusedAmount0);
        amount1 = SafeMath.add(amount1, unusedAmount1);
    }

    function _burnLiquidityShare(
        IUniswapV3Pool pool,
        ICHIVault vault,
        address yang,
        uint256 yangId,
        uint128 liquidity,
        uint256 shares,
        int24 tickLower,
        int24 tickUpper
    ) private view returns (uint256 amount0, uint256 amount1)
    {
        int128 liquidityDelta = SafeCast.toInt128(
                    -int256(FullMath.mulDiv(uint256(liquidity), shares, vault.totalSupply())
                ));
        if (liquidityDelta > 0) {
            // according to pool.burn calculate amount0, amount1
            (amount0, amount1) = _poolBurnShare(pool, tickLower, tickUpper, liquidityDelta);

            bytes32 poolPositionKey = PoolPosition.compute(yangId, address(vault), tickLower, tickUpper);
            bytes32 positionKey = PositionKey.compute(address(vault), tickLower, tickUpper);

            (uint256 collect0, uint256 collect1) = _poolCollectFee(pool, yang, poolPositionKey, positionKey);
            amount0 = amount0 > collect0 ? collect0 : amount0;
            amount1 = amount1 > collect1 ? collect1 : amount1;
        }
    }

    function _poolBurnShare(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) private view returns (uint256 amount0, uint256 amount1)
    {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        if (liquidityDelta != 0) {
            if (tick < tickLower) {
                amount0 = uint256(SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                ));
            } else if (tick < tickUpper) {
                amount0 = uint256(SqrtPriceMath.getAmount0Delta(
                    sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                ));
                amount1 = uint256(SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    sqrtPriceX96,
                    liquidityDelta
                ));
            } else {
                amount1 = uint256(SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                ));
            }
        }
    }

    function _collect(
        uint128 _liquidity,
        uint256 _feeGrowthInside0LastX128,
        uint256 _feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128
    ) private pure returns (uint256, uint256)
    {
        tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - _feeGrowthInside0LastX128,
                _liquidity,
                FixedPoint128.Q128
            )
        );
        tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - _feeGrowthInside1LastX128,
                _liquidity,
                FixedPoint128.Q128
            )
        );
        return (uint256(tokensOwed0), uint256(tokensOwed1));
    }

    function _poolCollectFee(
        IUniswapV3Pool pool,
        address yang,
        bytes32 poolPositionKey,
        bytes32 positionKey
    ) private view returns (uint256, uint256)
    {
        (
            uint128 _liquidity,
            uint256 _feeGrowthInside0LastX128,
            uint256 _feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = IYangNFTVault(yang).positions(poolPositionKey);

        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,
        ) = pool.positions(positionKey);

        return _collect(
            _liquidity,
            _feeGrowthInside0LastX128,
            _feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128
        );
    }

    function _positionLiquidity(
        IUniswapV3Pool pool,
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity)
    {
        (liquidity, , , , ) = pool.positions(PositionKey.compute(vault, tickLower, tickUpper));
    }
}
