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

import "./CHI.sol";
import "../interfaces/ICHIVault.sol";


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
        address _pool,
        address _vault,
        uint256 shares,
        CHI.VaultRange[] memory ranges
    )
        internal
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        ICHIVault vault = ICHIVault(_vault);
        uint256 totalSupply = vault.totalSupply();
        for (uint256 i = 0; i < ranges.length; i++) {
            CHI.VaultRange memory _range = ranges[i];
            uint128 liquidity = _positionLiquidity(pool, _vault, _range);
            if (liquidity > 0) {
                (uint256 _amount0, uint256 _amount1) = _burnLiquidityShare(
                                                            pool,
                                                            _vault,
                                                            liquidity,
                                                            shares,
                                                            totalSupply,
                                                            _range
                                                        );
                amount0 = SafeMath.add(amount0, _amount0);
                amount1 = SafeMath.add(amount1, _amount1);
            }
        }
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());
        uint256 unusedAmount0 = FullMath.mulDiv(
                    SafeMath.sub(token0.balanceOf(_vault), vault.accruedProtocolFees0()),
                    shares,
                    totalSupply
                );
        uint256 unusedAmount1 = FullMath.mulDiv(
                    SafeMath.sub(token1.balanceOf(_vault), vault.accruedProtocolFees1()),
                    shares,
                    totalSupply
                );
        amount0 = SafeMath.add(amount0, unusedAmount0);
        amount1 = SafeMath.add(amount1, unusedAmount1);
    }

    function _burnLiquidityShare(
        IUniswapV3Pool pool,
        address vault,
        uint128 liquidity,
        uint256 shares,
        uint256 totalSupply,
        CHI.VaultRange memory range
    ) internal returns (uint256 amount0, uint256 amount1)
    {
        int128 liquidityDelta = SafeCast.toInt128(
                    -int256(FullMath.mulDiv(uint256(liquidity), shares, totalSupply)
                ));
        int24 tickLower = range.tickLower;
        int24 tickUpper = range.tickUpper;
        if (liquidityDelta > 0) {
            // according to pool.burn calculate amount0, amount1
            (amount0, amount1) = _poolBurnShare(pool, tickLower, tickUpper, liquidityDelta);
            (uint256 collect0, uint256 collect1) = _poolCollectFee(pool, vault, tickLower, tickUpper);
            amount0 = SafeMath.add(amount0, collect0);
            amount1 = SafeMath.add(amount1, collect1);
        }
    }

    function _poolBurnShare(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) internal view returns (uint256 amount0, uint256 amount1)
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

    function _poolCollectFee(
        IUniswapV3Pool pool,
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256, uint256)
    {
        bytes32 key = keccak256(abi.encodePacked(vault, tickLower, tickUpper));
        (
            uint128 _liquidity,
            uint256 _feeGrowthInside0LastX128,
            uint256 _feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(key);

        pool.burn(tickLower, tickUpper, 0);
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,
        ) = pool.positions(key);

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
        return (tokensOwed0, tokensOwed1);
    }

    function _positionLiquidity(
        IUniswapV3Pool pool,
        address vault,
        CHI.VaultRange memory range
    ) internal view returns (uint128 liquidity)
    {
        bytes32 key = keccak256(abi.encodePacked(vault, range.tickLower, range.tickUpper));
        (liquidity, , , , ) = pool.positions(key);
    }
}
