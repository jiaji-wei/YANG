// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

library CHI {
    // info stored for each user's position

    struct MintParams {
        address recipient;
        address token0;
        address token1;
        uint24 fee;
        uint256 vaultFee;
    }
}
