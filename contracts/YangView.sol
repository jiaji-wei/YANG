// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./interfaces/ICHIVault.sol";
import "./interfaces/IYangView.sol";
import "./libraries/SharesHelper.sol";


contract YangView is IYangView
{
    address public yangNFT;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, 'only owner');
        _;
    }

    modifier onlyYang {
        require(msg.sender == yangNFT, 'only yang');
        _;
    }

    function setYangNFT(address _yangNFT)
        external override onlyOwner
    {
        yangNFT = _yangNFT;
    }

    function getSharesAndAmounts(
        address _vault,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        external
        override
        view
        onlyYang
        returns (uint256, uint256, uint256)
    {
        ICHIVault vault = ICHIVault(_vault);
        (uint256 totalAmount0, uint256 totalAmount1) = vault.getTotalAmounts();
        (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        ) = SharesHelper.calcSharesAndAmounts(
                totalAmount0,
                totalAmount1,
                amount0Desired,
                amount1Desired,
                vault.totalSupply()
            );
        return (shares, amount0, amount1);
    }

    function getAmounts(
        address _pool,
        address _vault,
        uint256 yangId,
        uint256 shares
    )
        external
        view
        onlyYang
        override
        returns (uint256 amount0, uint256 amount1)
    {
        ICHIVault vault = ICHIVault(_vault);
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (amount0, amount1) = SharesHelper.calcAmountsFromShares(
                pool,
                vault,
                msg.sender,
                yangId,
                shares
        );
    }
}
