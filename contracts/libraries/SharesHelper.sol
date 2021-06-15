 // SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

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
}
