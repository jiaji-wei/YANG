// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

interface ICHIVaultTest {
    function totalSupply() external view returns (uint256);
    function getTotalAmounts()
        external
        view
        returns (uint256 amount0, uint256 amount1);

    // For Test
    function accruedProtocolFees0() external view returns (uint256);
    function accruedProtocolFees1() external view returns (uint256);
    function protocolFee() external view returns (uint256);
    function deposit(
        uint256 yangId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 shares, uint256 amount0, uint256 amount1);
    function withdraw(
        uint256 yangId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    event Deposit(
        uint256 indexed yangId,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
    event Withdraw(
        uint256 indexed yangId,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
}

