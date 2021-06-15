// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/CHI.sol";

interface ICHIManager {
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
    function mint(CHI.MintParams memory params) external returns (uint256 chiId, address chiVault);
    function subscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 shares, uint256 amount0, uint256 amount1);
    function unsubscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    event Create(
        uint256 tokenId,
        address pool,
        address vault,
        uint256 vaultFee
    );
}

