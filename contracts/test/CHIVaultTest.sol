// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "../interfaces/ICHIVault.sol";
import "../interfaces/ICHIManager.sol";
import "../interfaces/ICHIDepositCallBack.sol";


contract CHIVaultTest is ICHIVault {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 private _accruedProtocolFees0 = 1e16;
    uint256 private _accruedProtocolFees1 = 1e16;
    uint256 private _protocolFee = 1e15;

    // total shares
    uint256 private _totalSupply;

    IUniswapV3Pool public pool;
    ICHIManager public CHIManager;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    constructor(
        address _pool,
        address _manager
    ) {
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        CHIManager = ICHIManager(_manager);
    }

    function _decode(uint256 num) internal pure returns (int24 num1, int24 num2) {
        num1 = int24(int256(num >> 128));
        num2 = int24(int256(num << 192) >> 192);
    }

    function _balanceToken0() internal view returns (uint256) {
        return token0.balanceOf(address(this)).sub(_accruedProtocolFees0);
    }

    function _balanceToken1() internal view returns (uint256) {
        return token1.balanceOf(address(this)).sub(_accruedProtocolFees1);
    }

    function getTotalAmounts() public view override returns (uint256 total0, uint256 total1) {
        total0 = total0.add(_balanceToken0());
        total1 = total1.add(_balanceToken1());
    }

    function _positionAmounts(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);
        (amount0, amount1) = _amountsForLiquidity(tickLower, tickUpper, liquidity);
        amount0 = amount0.add(uint256(tokensOwed0));
        amount1 = amount1.add(uint256(tokensOwed1));
    }

    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                                sqrtRatioX96,
                                TickMath.getSqrtRatioAtTick(tickLower),
                                TickMath.getSqrtRatioAtTick(tickUpper),
                                liquidity
                            );
    }

    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint128 liquidity) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
                        sqrtRatioX96,
                        TickMath.getSqrtRatioAtTick(tickLower),
                        TickMath.getSqrtRatioAtTick(tickUpper),
                        amount0,
                        amount1
                    );
    }

    function accruedProtocolFees0() external view virtual override returns (uint256) {
        return _accruedProtocolFees0;
    }

    function accruedProtocolFees1() external view virtual override returns (uint256) {
        return _accruedProtocolFees1;
    }

    function protocolFee() external view virtual override returns (uint256) {
        return _protocolFee;
    }

    function totalSupply() external view virtual override returns (uint256) {
        return _totalSupply;
    }

     /// @dev Increasing the total supply.
    function _mint(uint256 amount) internal {
        _totalSupply += amount;
    }

    /// @dev Decreasing the total supply.
    function _burn(uint256 amount) internal {
        _totalSupply -= amount;
    }

    function deposit(
        uint256 yangId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Desired > 0 || amount1Desired > 0, "a0a1");

        (shares, amount0, amount1) = _calcSharesAndAmounts(amount0Desired, amount1Desired);
        require(shares > 0, "s");
        require(amount0 >= amount0Min, "A0M");
        require(amount1 >= amount1Min, "A1M");

        // Pull in tokens from sender
        ICHIDepositCallBack(msg.sender).CHIDepositCallback(token0, amount0, token1, amount1);

        _mint(shares);
        emit Deposit(yangId, shares, amount0, amount1);
    }

    function withdraw(
        uint256 yangId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external override returns (uint256 amount0, uint256 amount1) {
        require(shares > 0, "s");
        require(to != address(0) && to != address(this), "to");

        uint256 unusedAmount0 = _balanceToken0().mul(shares).div(_totalSupply);
        uint256 unusedAmount1 = _balanceToken1().mul(shares).div(_totalSupply);
        if (unusedAmount0 > 0) token0.safeTransfer(to, unusedAmount0);
        if (unusedAmount1 > 0) token1.safeTransfer(to, unusedAmount1);

        // Sum up total amounts sent to recipient
        amount0 = unusedAmount0;
        amount1 = unusedAmount1;
        require(amount0 >= amount0Min, "A0M");
        require(amount1 >= amount1Min, "A1M");

        // Burn shares
        _burn(shares);
        emit Withdraw(yangId, to, shares, amount0, amount1);
    }

    function _calcSharesAndAmounts(uint256 amount0Desired, uint256 amount1Desired)
        internal
        view
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        (uint256 total0, uint256 total1) = getTotalAmounts();

        // If total supply > 0, vault can't be empty
        assert(_totalSupply == 0 || total0 > 0 || total1 > 0);

        if (_totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = Math.max(amount0, amount1);
        } else if (total0 == 0) {
            amount1 = amount1Desired;
            shares = amount1.mul(_totalSupply).div(total1);
        } else if (total1 == 0) {
            amount0 = amount0Desired;
            shares = amount0.mul(_totalSupply).div(total0);
        } else {
            uint256 cross = Math.min(amount0Desired.mul(total1), amount1Desired.mul(total0));
            require(cross > 0, "c");

            // Round up amounts
            amount0 = cross.sub(1).div(total1).add(1);
            amount1 = cross.sub(1).div(total0).add(1);
            shares = cross.mul(_totalSupply).div(total0).div(total1);
        }
    }

    function _burnLiquidityShare(
        int24 tickLower,
        int24 tickUpper,
        uint256 shares,
        address to
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint128 position = _positionLiquidity(tickLower, tickUpper);
        uint128 liquidity = toUint128(uint256(position).mul(shares).div(_totalSupply));

        if (liquidity > 0) {
            (amount0, amount1) = pool.burn(tickLower, tickUpper, liquidity);

            if (amount0 > 0 || amount1 > 0) {
                (amount0, amount1) = pool.collect(
                    to,
                    tickLower,
                    tickUpper,
                    toUint128(amount0),
                    toUint128(amount1)
                );
            }
        }
    }

    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @dev Get position liquidity
    function _positionLiquidity(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint128 liquidity)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity, , , , ) = pool.positions(positionKey);
    }
}
