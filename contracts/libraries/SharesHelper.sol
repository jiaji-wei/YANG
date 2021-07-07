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

    struct _burnShareParams {
        IUniswapV3Pool pool;
        ICHIVault vault;
        address yang;
        uint256 yangId;
        uint128 liquidity;
        uint256 shares;
        int24 tickLower;
        int24 tickUpper;
    }

    struct _poolCollectParams {
        IUniswapV3Pool pool;
        address yang;
        bytes32 key0;
        bytes32 key1;
        uint256 collect0;
        uint256 collect1;
    }

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
        assert(totalSupply == 0 || totalAmount0 > 0 || totalAmount1 > 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = Math.max(amount0, amount1);
        } else if (totalAmount0 == 0) {
            amount1 = amount1Desired;
            shares = FullMath.mulDiv(amount1, totalSupply, totalAmount1);
        } else if (totalAmount1 == 0) {
            amount0 = amount0Desired;
            shares = FullMath.mulDiv(amount0, totalSupply, totalAmount0);
        } else {
            uint256 cross = Math.min(
                                SafeMath.mul(amount0Desired, totalAmount1),
                                SafeMath.mul(amount1Desired, totalAmount0)
                            );
            require(cross > 0, "c");

            // Round up amounts
            amount0 = SafeMath.add(SafeMath.div(SafeMath.sub(cross, 1), totalAmount1), 1);
            amount1 = SafeMath.add(SafeMath.div(SafeMath.sub(cross, 1), totalAmount0), 1);
            shares = SafeMath.div(FullMath.mulDiv(cross, totalSupply, totalAmount0), totalAmount1);
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
            uint128 liquidity = PoolPosition._poolLiquidity(pool, address(vault), tickLower, tickUpper);
            if (liquidity > 0) {
                _burnShareParams memory params = _burnShareParams({
                                        pool: pool,
                                        vault:vault,
                                        yang: yang,
                                        yangId: yangId,
                                        liquidity: liquidity,
                                        shares: shares,
                                        tickLower: tickLower,
                                        tickUpper: tickUpper
                                    });
                (uint256 _amount0, uint256 _amount1) = _burnShare(params);
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

    function _burnShare(_burnShareParams memory params)
        private view returns (uint256 amount0, uint256 amount1)
    {
        int128 liquidityDelta = SafeCast.toInt128(
                    -int256(FullMath.mulDiv(uint256(params.liquidity),
                                            params.shares,
                                            params.vault.totalSupply())
                    ));
        if (liquidityDelta > 0) {
            // according to pool.burn calculate amount0, amount1
            uint256 yangId = params.yangId;
            (uint256 collect0, uint256 collect1) = _poolBurn(
                    params.pool, params.tickLower, params.tickUpper, liquidityDelta);

            bytes32 key0 = PoolPosition.compute(yangId, address(params.vault), params.tickLower, params.tickUpper);
            bytes32 key1 = PositionKey.compute(address(params.vault), params.tickLower, params.tickUpper);

            _poolCollectParams memory _params = _poolCollectParams({
                        pool: params.pool,
                        yang: params.yang,
                        key0: key0,
                        key1: key1,
                        collect0: collect0,
                        collect1: collect1
                    });
            (uint256 tokensOwed0, uint256 tokensOwed1) = _poolCollect(params.tickLower, params.tickUpper, _params);
            amount0 = collect0 > tokensOwed0 ? tokensOwed0 : collect0;
            amount1 = collect1 > tokensOwed1 ? tokensOwed1 : collect1;
        }
    }

    function _poolBurn(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) private view returns (uint256, uint256)
    {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        int256 amount0;
        int256 amount1;
        if (liquidityDelta != 0) {
            if (tick < tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                );
            } else if (tick < tickUpper) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    sqrtPriceX96,
                    liquidityDelta
                );
            } else {
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                );
            }
        }
        return (uint256(-amount0), uint256(-amount1));
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

    function _getFeeGrowthInside(IUniswapV3Pool pool, bytes32 key, int24 tickLower, int24 tickUpper)
        private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        (
            ,
            uint256 _feeGrowthInside0LastX128,
            uint256 _feeGrowthInside1LastX128,
            ,
        ) = pool.positions(key);
        (, int24 tickCurrent, , , , , ) = pool.slot0();

        // calculate fee growth below
        (,,uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower,,,,) = pool.ticks(tickLower);
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = feeGrowthOutside0X128Lower;
            feeGrowthBelow1X128 = feeGrowthOutside1X128Lower;
        } else {
            feeGrowthBelow0X128 = _feeGrowthInside0LastX128 - feeGrowthOutside0X128Lower;
            feeGrowthBelow1X128 = _feeGrowthInside1LastX128 - feeGrowthOutside1X128Lower;
        }

        (,,uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper,,,,) = pool.ticks(tickUpper);

        // calculate fee growth above
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = feeGrowthOutside0X128Upper;
            feeGrowthAbove1X128 = feeGrowthOutside1X128Upper;
        } else {
            feeGrowthAbove0X128 = _feeGrowthInside0LastX128 - feeGrowthOutside0X128Upper;
            feeGrowthAbove1X128 = _feeGrowthInside1LastX128 - feeGrowthOutside1X128Upper;
        }

        feeGrowthInside0X128 = _feeGrowthInside0LastX128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = _feeGrowthInside1LastX128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    function _poolCollect(
        int24 tickLower,
        int24 tickUpper,
        _poolCollectParams memory params)
        private view returns (uint256, uint256)
    {
        (
            uint128 _liquidity,
            uint256 _feeGrowthInside0LastX128,
            uint256 _feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = IYangNFTVault(params.yang).poolPositions(params.key0);

        (
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        ) = _getFeeGrowthInside(params.pool, params.key1, tickLower, tickUpper);

        return _collect(
            _liquidity,
            _feeGrowthInside0LastX128,
            _feeGrowthInside1LastX128,
            tokensOwed0 + uint128(params.collect0),
            tokensOwed1 + uint128(params.collect1),
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128
        );
    }

    function getSharesAndAmounts(
        address _vault,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        internal
        view
        returns (uint256, uint256, uint256)
    {
        ICHIVault vault = ICHIVault(_vault);
        (uint256 totalAmount0, uint256 totalAmount1) = vault.getTotalAmounts();
        (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        ) = calcSharesAndAmounts(
                totalAmount0,
                totalAmount1,
                amount0Desired,
                amount1Desired,
                vault.totalSupply()
            );
        return (shares, amount0, amount1);
    }

    function getAmounts(
        address _pool,
        address _vault,
        uint256 yangId,
        uint256 shares
    )
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        ICHIVault vault = ICHIVault(_vault);
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (amount0, amount1) = calcAmountsFromShares(
                pool,
                vault,
                msg.sender,
                yangId,
                shares
        );
    }
}
