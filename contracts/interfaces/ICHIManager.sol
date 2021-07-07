// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma abicoder v2;

import './ICHIDepositCallBack.sol';

interface ICHIManager is ICHIDepositCallBack {
    struct MintParams {
        address recipient;
        address token0;
        address token1;
        uint24 fee;
        uint256 vaultFee;
    }

    function chi(uint256 tokenId)
        external
        view
        returns (
            address owner,
            address operator,
            address pool,
            address vault,
            uint256 accruedProtocolFees0,
            uint256 accruedProtocolFees1,
            uint256 fee,
            uint256 totalShares
        );

    function mint(MintParams calldata params) external returns (uint256 tokenId, address vault);

    function subscribe(
        uint256 yangId,
        uint256 tokenId,
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

    function unsubscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1);

    function addRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) external;

    function removeRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) external;

    function collectProtocol(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external;

    function addLiquidityToPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external;

    function removeLiquidityFromPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint128 liquidity
    ) external;

    function removeAllLiquidityFromPosition(uint256 tokenId, uint256 rangeIndex) external;

    event Create(uint256 tokenId, address pool, address vault, uint256 vaultFee);
}
