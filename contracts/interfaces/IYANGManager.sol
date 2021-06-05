// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

interface IYANGManager {

    function mint(address recipient) external returns (uint256);

    function addPool(address token0, address token1) external;

    function deposit(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external;

    function deposit(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external;

    function subscribeCHI(
        uint256 tokenId,
        address token0
        uint256 amount0,
        uint256 amount0Min
        address token1,
        uint256 amount1,
        uint256 amount1Min
    ) external returns (uint256);

    function unsubscribeCHI(
        uint256 tokenId,
        uint256 chiId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
    ) external;

    event CreateNFT(address indexed recipient, uint256 indexed tokenId);
}
