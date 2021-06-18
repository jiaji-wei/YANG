// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma abicoder v2;

interface IYangNFTVault {

    struct SubscribeParam {
        uint256 yangId;
        uint256 chiId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct UnSubscribeParam {
        uint256 yangId;
        uint256 chiId;
        uint256 shares;
        uint256 amount0Min;
        uint256 amount1Min;
        // address recipient;
        // recipient is tricky wait for confirm.
    }

    event MintYangNFT(address indexed recipient, uint256 indexed tokenId);
    event Deposit(uint256 indexed tokenId, address indexed token0, address token1);
    event Withdraw(uint256 indexed tokenId, address indexed token0, address token1);
    event Subscribe(uint256 indexed yangId, uint256 indexed chiId, uint256 indexed share);
    event UnSubscribe(uint256 indexed yangId, uint256 indexed chiId, uint256 amount0, uint256 amount1);

    function setCHIManager(address) external;
    function setYangView(address) external;
    function mint(address recipient) external returns (uint256 tokenId);
    function deposit(uint256 tokenId, address token0, uint256 amount0, address token1, uint256 amount1) external;
    function withdraw(uint256 tokenId, address token0, uint256 amount0, address token1, uint256 amount1) external;
    function subscribe(SubscribeParam memory params) external returns (uint256 share);
    function unsubscribe(UnSubscribeParam memory params) external;
    function positions(bytes32)
        external
        view
        returns (uint128, uint256, uint256, uint128, uint128);
    function getShares(
        uint256 chiId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint256);
    function getAmounts(
        uint256 yangId,
        uint256 chiId,
        address user
    ) external view returns (uint256, uint256);
}
