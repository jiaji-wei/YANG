# YangNFTVault ABI

## Interfaces

### getTokenId

```
function getTokenId(address recipient) external view return (uin256);
```

return recipient tokenId >= 1

### Mint
```
function mint(address recipient) external returns (uint256 tokenId);
```

* address recipient: mint yang tokenId for recipient

event **MintYangNFT(address indexed recipient, uint256 indexed tokenId)**

### deposit

```
function deposit(
    uint256 tokenId,
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1
) external;
```

* uint256 tokenId: YangNFTVault NFT tokenId
* address token0: deposit token0
* uint256 amount0: deposit amount0
* address token1: deposit token1
* uint256 amount1: deposit amount1

Event **Deposit(uint256 indexed tokenId, address indexed token0, address indexed token1)**

### withdraw

```
function withdraw(
    uint256 tokenId,
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1
) external;

```

* uint256 tokenId: YangNFTVault NFT tokenId
* address token0: withdraw token0
* uint256 amount0: withdraw amount0
* address token1: withdraw token1
* uint256 amount1: withdraw amount1

Event **Withdraw(uint256 indexed tokenId, address indexed token0, address indexed token1)**

### subscribe

```
function subscribe(SubscribeParam memory params) returns (uint256 share) external;
```

* uint256 share: user subscribe amount share prove

```
struct SubscribeParam {
    uint256 yangId;
    uint256 chiId;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}
```

* uint256 yangId: YangNFTVault NFT tokenId
* uint256 chiId: CHIManagement NFT tokenId
* uint256 amount0Desired: token0 amount to subscribe
* uint256 amount1Desired: token1 amount to subscribe
* uint256 amount0Min: token0 miniumn amount to subscribe
* uint256 amount1Min: token1 miniumn amount to subscribe

Event **Subscribe(uint256 indexed yangId, uint256 indexed chiId, uint256 indexed share)**


### unsubscribe

```
function unsubscribe(UnSubscribeParam memory params) external;
```

```
struct UnSubscribeParam {
    uint256 yangId;
    uint256 chiId;
    uint256 shares;
    uint256 amount0Min;
    uint256 amount1Min;
}
```

* uint256 yangId: YangNFTVault NFT tokenId
* uint256 chiId: CHIManagement NFT tokenId
* uint256 shares: user want to unsubscribe shares
* uint256 amount0Min: token0 miniumn amount to unsubscribe
* uint256 amount1Min: token1 miniumn amount to unsubscribe

### getShares

```
function getShares(
    uint256 chiId,
    uint256 amount0Desired,
    uint256 amount1Desired
) external view returns (uint256 shares, uint256 amount0, uint256 amount1);
```

To calculate **amount0Desired** and **amount1Desired** in CHI **chiId** 

get how many **shares** and actually cost **amount0** and **amount1**

* uint256 chiId: CHI Management NFT tokenId
* uint256 amount0Desired: token0 amount wanted
* uint256 amount1Desired: token1 amount wanted

### getAmounts

```
function getAmounts(
    uint256 yangId,
    uint256 chiId,
    address user
) external returns (uint256 amount0, uint256 amount1);
```

To calcualte token0 **amount0** and token1 **amount1**

* uint256 yangId: YangNFTVault NFT tokenId
* uint256 chiId: CHI Management NFT tokenId
* address user: calculate user amounts

