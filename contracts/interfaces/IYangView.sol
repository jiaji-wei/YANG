// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;


interface IYangView {

    function setYangNFT(address _yangNFT) external;
    function getSharesAndAmounts(
        address _vault,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint256, uint256, uint256);
    function getAmounts(
        address _pool,
        address _vault,
        uint256 yangId,
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1);
}
