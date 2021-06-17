// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

interface ICHIVault {
    function totalSupply() external view returns (uint256);
    function getTotalAmounts()
        external
        view
        returns (uint256 amount0, uint256 amount1);
    function getRangeCount() external view returns (uint);
    function getRange(uint256 index) external view returns (int24 tickLower, int24 tickUpper);
    function accruedProtocolFees0() external view returns (uint256);
    function accruedProtocolFees1() external view returns (uint256);
    function protocolFee() external view returns (uint256);
}
