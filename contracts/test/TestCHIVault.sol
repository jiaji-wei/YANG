// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';

import '../interfaces/ICHIDepositCallBack.sol';
import '../interfaces/ICHIVault.sol';
import '../interfaces/ICHIManager.sol';

contract TestCHIVault is ICHIVault, IUniswapV3MintCallback {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Deposit(uint256 indexed yangId, uint256 shares, uint256 amount0, uint256 amount1);

    event Withdraw(uint256 indexed yangId, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);

    event CollectFee(uint256 feesFromPool0, uint256 feesFromPool1);

    IUniswapV3Pool public pool;
    ICHIManager public CHIManager;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    int24 public immutable tickSpacing;

    uint256 private _accruedProtocolFees0;
    uint256 private _accruedProtocolFees1;
    uint256 private _protocolFee;
    uint256 public FEE_BASE = 1e6;

    // total shares
    uint256 private _totalSupply;

    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet private _rangeSet;

    constructor(
        address _pool,
        address _manager,
        uint256 _protocolFee_
    ) {
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        tickSpacing = pool.tickSpacing();

        CHIManager = ICHIManager(_manager);

        _protocolFee = _protocolFee_;

        require(_protocolFee < FEE_BASE, 'f');
    }

    modifier onlyManager {
        require(msg.sender == address(CHIManager), 'm');
        _;
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

    function getRangeCount() external view virtual override returns (uint256) {
        return _rangeSet.length();
    }

    function _encode(int24 num1, int24 num2) internal pure returns (uint256 value) {
        value = ((uint256(int256(num1)) << 232) >> 104) + ((uint256(int256(num2)) << 232) >> 232);
    }

    function _decode(uint256 num) internal pure returns (int24 num1, int24 num2) {
        num1 = int24(int256(num >> 128));
        num2 = int24(int256(num << 192) >> 192);
    }

    function getRange(uint256 index) external view virtual override returns (int24 tickLower, int24 tickUpper) {
        (tickLower, tickUpper) = _decode(_rangeSet.at(index));
    }

    function addRange(int24 tickLower, int24 tickUpper) external override onlyManager {
        (uint256 amount0, uint256 amount1) = _positionAmounts(tickLower, tickUpper);
        require(amount0 == 0, 'a0');
        require(amount1 == 0, 'a0');
        _checkTicks(tickLower, tickUpper);
        _rangeSet.add(_encode(tickLower, tickUpper));
    }

    function removeRange(int24 tickLower, int24 tickUpper) external override onlyManager {
        (uint256 amount0, uint256 amount1) = _positionAmounts(tickLower, tickUpper);
        require(amount0 == 0, 'a0');
        require(amount1 == 0, 'a0');
        _rangeSet.remove(_encode(tickLower, tickUpper));
    }

    function getTotalAmounts() public view override returns (uint256 total0, uint256 total1) {
        for (uint256 i = 0; i < _rangeSet.length(); i++) {
            (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(i));
            (uint256 amount0, uint256 amount1) = _positionAmounts(_tickLower, _tickUpper);
            total0 = total0.add(amount0);
            total1 = total1.add(amount1);
        }
        total0 = total0.add(_balanceToken0());
        total1 = total1.add(_balanceToken1());
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
        onlyManager
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Desired > 0 || amount1Desired > 0, 'a0a1');

        // update pool
        _updateLiquidity();

        (shares, amount0, amount1) = _calcSharesAndAmounts(amount0Desired, amount1Desired);
        require(shares > 0, 's');
        require(amount0 >= amount0Min, 'A0M');
        require(amount1 >= amount1Min, 'A1M');

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
    ) external override onlyManager returns (uint256 amount0, uint256 amount1) {
        require(shares > 0, 's');
        require(to != address(0) && to != address(this), 'to');

        (uint256 removeAmount0, uint256 removeAmount1) = _burnMultLiquidityShare(shares, to);

        uint256 unusedAmount0 = _balanceToken0().mul(shares).div(_totalSupply);
        uint256 unusedAmount1 = _balanceToken1().mul(shares).div(_totalSupply);

        if (unusedAmount0 > 0) token0.safeTransfer(to, unusedAmount0);
        if (unusedAmount1 > 0) token1.safeTransfer(to, unusedAmount1);

        // Sum up total amounts sent to recipient
        amount0 = removeAmount0.add(unusedAmount0);
        amount1 = removeAmount1.add(unusedAmount1);
        require(amount0 >= amount0Min, 'A0M');
        require(amount1 >= amount1Min, 'A1M');

        // Burn shares
        _burn(shares);
        emit Withdraw(yangId, to, shares, amount0, amount1);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external override {
        require(msg.sender == address(pool));
        if (amount0Owed > 0) token0.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(msg.sender, amount1Owed);
    }

    function _balanceToken0() internal view returns (uint256) {
        return token0.balanceOf(address(this)).sub(_accruedProtocolFees0);
    }

    function _balanceToken1() internal view returns (uint256) {
        return token1.balanceOf(address(this)).sub(_accruedProtocolFees1);
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
            require(cross > 0, 'c');

            // Round up amounts
            amount0 = cross.sub(1).div(total1).add(1);
            amount1 = cross.sub(1).div(total0).add(1);
            shares = cross.mul(_totalSupply).div(total0).div(total1);
        }
    }

    function harvestFee() external override {
        uint256 collect0 = 0;
        uint256 collect1 = 0;
        // update pool
        _updateLiquidity();
        for (uint256 i = 0; i < _rangeSet.length(); i++) {
            (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(i));
            (uint256 _collect0, uint256 _collect1) = _collet(_tickLower, _tickUpper);
            collect0 = collect0.add(_collect0);
            collect1 = collect1.add(_collect1);
        }
        emit CollectFee(collect0, collect1);
    }

    function collectProtocol(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external override onlyManager {
        _accruedProtocolFees0 = _accruedProtocolFees0.sub(amount0);
        _accruedProtocolFees1 = _accruedProtocolFees1.sub(amount1);
        if (amount0 > 0) token0.safeTransfer(to, amount0);
        if (amount1 > 0) token1.safeTransfer(to, amount1);
    }

    function addLiquidityToPosition(
        uint256 rangeIndex,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external override onlyManager {
        (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(rangeIndex));

        require(amount0Desired <= _balanceToken0(), 'IB0');
        require(amount1Desired <= _balanceToken1(), 'IB1');

        // Place order on UniswapV3
        uint128 liquidity = _liquidityForAmounts(_tickLower, _tickUpper, amount0Desired, amount1Desired);
        if (liquidity > 0) {
            pool.mint(address(this), _tickLower, _tickUpper, liquidity, new bytes(0));
        }
    }

    function removeLiquidityFromPosition(uint256 rangeIndex, uint128 liquidity)
        external
        override
        onlyManager
        returns (uint256 amount0, uint256 amount1)
    {
        (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(rangeIndex));

        require(liquidity <= _positionLiquidity(_tickLower, _tickUpper), 'L');

        if (liquidity > 0) {
            (amount0, amount1) = pool.burn(_tickLower, _tickUpper, liquidity);

            if (amount0 > 0 || amount1 > 0) {
                (amount0, amount1) = pool.collect(
                    address(this),
                    _tickLower,
                    _tickUpper,
                    toUint128(amount0),
                    toUint128(amount1)
                );
            }
        }
    }

    function removeAllLiquidityFromPosition(uint256 rangeIndex)
        external
        override
        onlyManager
        returns (uint256 amount0, uint256 amount1)
    {
        (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(rangeIndex));
        uint128 liquidity = _positionLiquidity(_tickLower, _tickUpper);
        if (liquidity > 0) {
            (amount0, amount1) = pool.burn(_tickLower, _tickUpper, liquidity);

            if (amount0 > 0 || amount1 > 0) {
                (amount0, amount1) = pool.collect(
                    address(this),
                    _tickLower,
                    _tickUpper,
                    toUint128(amount0),
                    toUint128(amount1)
                );
            }
        }
    }

    function _collet(int24 tickLower, int24 tickUpper) internal returns (uint256 collect0, uint256 collect1) {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);
        (collect0, collect1) = pool.collect(address(this), tickLower, tickUpper, tokensOwed0, tokensOwed1);
        uint256 feesToProtocol0 = 0;
        uint256 feesToProtocol1 = 0;

        // Update accrued protocol fees
        if (_protocolFee > 0) {
            feesToProtocol0 = collect0.mul(_protocolFee).div(FEE_BASE);
            feesToProtocol1 = collect1.mul(_protocolFee).div(FEE_BASE);
            _accruedProtocolFees0 = _accruedProtocolFees0.add(feesToProtocol0);
            _accruedProtocolFees1 = _accruedProtocolFees1.add(feesToProtocol1);
        }
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

    function _checkTicks(int24 tickLower, int24 tickUpper) private view {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
        require(tickLower % tickSpacing == 0, 'TLF');
        require(tickUpper % tickSpacing == 0, 'TUF');
    }

    function _updateLiquidity() internal {
        for (uint256 i = 0; i < _rangeSet.length(); i++) {
            (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(i));
            if (_positionLiquidity(_tickLower, _tickUpper) > 0) {
                pool.burn(_tickLower, _tickUpper, 0);
            }
        }
    }

    function _burnMultLiquidityShare(uint256 shares, address to) internal returns (uint256 total0, uint256 total1) {
        for (uint256 i = 0; i < _rangeSet.length(); i++) {
            (int24 _tickLower, int24 _tickUpper) = _decode(_rangeSet.at(i));
            if (_positionLiquidity(_tickLower, _tickUpper) > 0) {
                (uint256 amount0, uint256 amount1) = _burnLiquidityShare(_tickLower, _tickUpper, shares, to);
                total0 = total0.add(amount0);
                total1 = total1.add(amount1);
            }
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
                (amount0, amount1) = pool.collect(to, tickLower, tickUpper, toUint128(amount0), toUint128(amount1));
            }
        }
    }

    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @dev Get position liquidity
    function _positionLiquidity(int24 tickLower, int24 tickUpper) internal view returns (uint128 liquidity) {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity, , , , ) = pool.positions(positionKey);
    }

    /// @dev Increasing the total supply.
    function _mint(uint256 amount) internal {
        _totalSupply += amount;
    }

    /// @dev Decreasing the total supply.
    function _burn(uint256 amount) internal {
        _totalSupply -= amount;
    }
}
