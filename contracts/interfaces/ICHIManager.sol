// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/CHI.sol";

interface ICHIManager {

    function mint(CHI.MintParams memory params) external returns (uint256 chiId, address chiVaule);
}
