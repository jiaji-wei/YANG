// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma abicoder v2;

interface IYangNFTVault {
    struct YangPosition {
        address token;
        uint256 balance;
    }

    struct ChiPosition {
        address pool;
        address vault;
        uint256 shares;
    }

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
        address recipient;
    }

    event MintYangNFT(address indexed recipient, uint256 indexed tokenId);
    event Deposit(uint256 indexed tokenId, address indexed token, uint256 indexed amount, address user);
    event Withdraw(uint256 indexed tokenId, address indexed token, uint256 indexed amount, address user);
    event Subscribe(uint256 indexed yangId, uint256 indexed chiId, uint256 indexed shares);
    event UnSubscribe(uint256 indexed yangId, uint256 indexed chiId, uint256 amount0, uint256 amount1);

    function mint(address recipient) external returns (uint256 tokenId);
    function deposit(uint256 tokenId, address token, uint256 amount) external;
    function withdraw(uint256 tokenId, address token, uint256 amount, address recipient) external;
    function subscribe(SubscribeParam memory params) external;
    function unsubscribe(UnSubscribeParam memory params) external;
}
