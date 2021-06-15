// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYANGCallBack {
    function DepositCallBack(address user, IERC20 token0, uint256 amount0, IERC20 token1, uint256 amount1) external;
    function WithdrawCallBack(address user, IERC20 token0, uint256 amount0, IERC20 token1, uint256 amount1) external;
}
