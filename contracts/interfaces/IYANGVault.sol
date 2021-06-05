// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

interface IYANGVault {

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
