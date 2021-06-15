// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

interface IYANGVault {

    event Deposit(
        uint256 indexed yangId,
        uint256 amount0,
        uint256 amount1
    );

    event Withdraw(
        uint256 indexed yangId,
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );

    function deposit(
        uint256 yangId,
        address user,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external;

    function withdraw(
        uint256 yangId,
        address user,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external;

    function getVaultFee() external returns(uint256);
    function setVaultFee(uint256 fee) external;
    function addPool(address token0, address token1) external;
    function poolLength() external view returns (uint256 length);
    function tokenLength() external view returns (uint256 length);
    function showPoolAt(uint256 index) external view returns (address token0, address token1);
    function showTokenAt(uint256 index) external view returns (address token);
}
