// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

library YangPosition {
    struct Info {
        uint256 amount0;
        uint256 amount1;
        uint256 shares;
    }

    function get(
        mapping(bytes32 => Info) storage self,
        uint256 yangId,
        uint256 chiId
    ) internal view returns (YangPosition.Info storage position)
    {
        position = self[keccak256(abi.encodePacked(yangId, chiId))];
    }
}
