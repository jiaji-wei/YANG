// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

interface ICHIVault {
    // fee
    function accruedProtocolFees0() external view returns (uint256);

    function accruedProtocolFees1() external view returns (uint256);

    function protocolFee() external view returns (uint256);

    // shares
    function totalSupply() external view returns (uint256);

    // range
    function getRangeCount() external view returns (uint256);

    function getRange(uint256 index) external view returns (int24 tickLower, int24 tickUpper);

    function addRange(int24 _tickLower, int24 _tickUpper) external;

    function removeRange(int24 _tickLower, int24 _tickUpper) external;

    function getTotalAmounts() external view returns (uint256 amount0, uint256 amount1);

    function harvestFee() external;

    function collectProtocol(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external;

    function deposit(
        uint256 yangId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        );

    function withdraw(
        uint256 yangId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function addLiquidityToPosition(
        uint256 _rangeIndex,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external;

    function removeLiquidityFromPosition(uint256 rangeIndex, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1);

    function removeAllLiquidityFromPosition(uint256 rangeIndex) external returns (uint256 amount0, uint256 amount1);
}
