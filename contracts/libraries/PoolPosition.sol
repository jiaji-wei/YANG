// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

import "../interfaces/ICHIVault.sol";


library PoolPosition {
    struct Info {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function compute(
        uint256 yangId,
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32)
    {
       return keccak256(abi.encodePacked(yangId, vault, tickLower, tickUpper));
    }

    function get(
        mapping(bytes32 => Info) storage self,
        uint256 yangId,
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (PoolPosition.Info storage position)
    {
        position = self[compute(yangId, vault, tickLower, tickUpper)];
    }

    function update(
        Info storage self,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) internal
    {
        self.liquidity = liquidity;
        self.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        self.tokensOwed0 = tokensOwed0;
        self.tokensOwed1 = tokensOwed1;
    }

    function set(
        mapping(bytes32 => Info) storage self,
        IUniswapV3Pool pool,
        ICHIVault vault,
        uint256 yangId
    ) internal
    {
        for (uint i = 0; i < vault.getRangeCount(); i++) {
            (int24 tickLower, int24 tickUpper) = vault.getRange(i);
            PoolPosition.Info storage position = get(self, yangId, address(vault), tickLower, tickUpper);
            (
                uint128 _liquidity,
                uint256 feeGrowthInside0LastX128,
                uint256 feeGrowthInside1LastX128,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) = pool.positions(PositionKey.compute(address(vault), tickLower, tickUpper));
            update(
                position,
                _liquidity,
                feeGrowthInside0LastX128,
                feeGrowthInside1LastX128,
                tokensOwed0,
                tokensOwed1
            );
        }
    }

    function free(
        mapping(bytes32 => Info) storage self,
        ICHIVault vault,
        uint256 yangId
    ) internal
    {
        for (uint i = 0; i < vault.getRangeCount(); i++) {
            (int24 tickLower, int24 tickUpper) = vault.getRange(i);
            delete self[compute(yangId, address(vault), tickLower, tickUpper)];
        }
    }
}
