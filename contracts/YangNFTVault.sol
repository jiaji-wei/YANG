// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/CHI.sol";
import "./libraries/PoolPosition.sol";
import "./libraries/SharesHelper.sol";
import "./interfaces/IYangNFTVault.sol";
import "./interfaces/ICHIManager.sol";
import "./interfaces/ICHIVault.sol";


contract YangNFTVault is
    IYangNFTVault,
    ReentrancyGuard,
    ERC721
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using PoolPosition for mapping(bytes32 => PoolPosition.Info);
    using PoolPosition for PoolPosition.Info;

    // owner
    address public owner;
    modifier onlyOwner {
        require(msg.sender == owner, 'only owner');
        _;
    }

    // nft and Yang tokenId
    mapping(address => uint256) private _userTokenTracker;
    mapping(bytes32 => bool) private _userExists;
    Counters.Counter private _tokenIdTracker;
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'not approved');
        _;
    }

    // yangPosition
    mapping(bytes32 => YangPosition) private _yangPositions;
    EnumerableSet.Bytes32Set private _yangPositionSet;

    // chiPosition
    mapping(bytes32 => ChiPosition) private _chiPositions;
    EnumerableSet.Bytes32Set private _chiPositionSet;

    // poolPosition
    mapping(bytes32 => PoolPosition.Info) private _poolPositions;

    // chiManager
    address private _chiManager;

    constructor() ERC721("YANG's Asset Manager", "YANG")
    {
        owner = msg.sender;
    }

    function setCHIManager(address _chiManagerAddr) external onlyOwner
    {
        _chiManager = _chiManagerAddr;
    }

    function mint(address recipient)
        external
        override
        returns (uint256 tokenId)
    {
        tokenId = _tokenIdTracker.current();
        bytes32 key = keccak256(abi.encodePacked(recipient, tokenId));
        require(_userExists[key] == false, "already exists");

        // _mint function check tokenId existence
        _mint(recipient, tokenId);
        _tokenIdTracker.increment();
        _userTokenTracker[recipient] = tokenId;
        _userExists[key] = true;

        emit MintYangNFT(recipient, tokenId);
    }

    function deposit(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external override isAuthorizedForToken(tokenId) nonReentrant
    {
        require(amount0 > 0, 'deposit need nonzero amount0');
        require(amount1 > 0, 'deposit need nonzero amount1');
        _deposit(tokenId, token0, amount0);
        _deposit(tokenId, token1, amount1);
        emit Deposit(tokenId, token0, token1);
    }

    function _deposit(uint256 tokenId, address token, uint256 amount)
        internal
        isAuthorizedForToken(tokenId)
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _increasePosition(tokenId, token, amount);
    }

    function _increasePosition(uint256 tokenId, address token, uint256 amount) internal
    {
        bytes32 key = keccak256(abi.encodePacked(tokenId, msg.sender, token));
        if (_yangPositionSet.contains(key)) {
            YangPosition storage position = _yangPositions[key];
            position.balance = position.balance.add(amount);
        } else {
            _yangPositionSet.add(key);
            _yangPositions[key] = YangPosition({
                token: token,
                balance: amount
            });
        }
    }

    function _decreasePosition(uint256 tokenId, address token, uint256 amount) internal
    {
        bytes32 key = keccak256(abi.encodePacked(tokenId, msg.sender, token));
        require(_yangPositionSet.contains(key), 'missing position');
        YangPosition storage position = _yangPositions[key];
        require(position.balance >= amount, 'insufficient balance');
        position.balance = position.balance.sub(amount);
    }

    function _withdraw(uint256 tokenId, address token, uint256 amount)
        internal
        isAuthorizedForToken(tokenId)
    {
        _decreasePosition(tokenId, token, amount);
        IERC20(token).safeTransferFrom(address(this), msg.sender, amount);
    }

    function withdraw(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external override isAuthorizedForToken(tokenId) nonReentrant
    {
        require(amount0 > 0, 'withdraw need nonzero amount0');
        require(amount1 > 0, 'withdraw need nonzero amount1');
        _withdraw(tokenId, token0, amount0);
        _withdraw(tokenId, token1, amount1);
        emit Withdraw(tokenId, token0, token1);
    }

    function subscribe(IYangNFTVault.SubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
        nonReentrant
        returns (uint256)
    {
        require(_chiManager != address(0), 'prepare chi manager first');
        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(_chiManager).chi(params.chiId);
        require(params.amount0Desired >= params.amount0Min, 'desired amount insufficient');
        require(params.amount1Desired >= params.amount1Min, 'desired amount insufficient');
        (
            uint256 share,
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(_chiManager).subscribe(
                params.yangId,
                params.chiId,
                params.amount0Desired,
                params.amount1Desired,
                params.amount0Min,
                params.amount1Min
            );
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        _decreasePosition(params.yangId, pool.token0(), amount0);
        _decreasePosition(params.yangId, pool.token1(), amount1);

        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId, msg.sender));
        if (_chiPositionSet.contains(key)) {
            ChiPosition storage position = _chiPositions[key];
            position.shares = position.shares.add(share);
            position.amounts0 = position.amounts0.add(amount0);
            position.amounts1 = position.amounts1.add(amount1);
        } else {
            _chiPositionSet.add(key);
            _chiPositions[key] = ChiPosition({
                pool: _pool,
                vault: _vault,
                shares: share,
                amounts0: amount0,
                amounts1: amount1
            });
        }

        ICHIVault vault = ICHIVault(_vault);
        _poolPositions.set(pool, vault, params.yangId);
        emit Subscribe(params.yangId, params.chiId, share);
        return share;
    }

    function unsubscribe(IYangNFTVault.UnSubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
        nonReentrant
    {
        require(_chiManager != address(0), 'prepare chi manager first');
        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(_chiManager).chi(params.chiId);
        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId, msg.sender));
        require(_chiPositionSet.contains(key), 'missing chi position');

        ChiPosition storage position = _chiPositions[key];
        require(position.shares >= params.shares, 'insufficient shares');
        (
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(_chiManager).unsubscribe(
                params.yangId,
                params.chiId,
                params.shares,
                params.amount0Min,
                params.amount1Min,
                address(this)
            );
        position.shares = position.shares.sub(params.shares);
        position.amounts0 = position.amounts0.sub(amount0);
        position.amounts1 = position.amounts1.sub(amount1);

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        _increasePosition(params.yangId, pool.token0(), amount0);
        _increasePosition(params.yangId, pool.token1(), amount1);

        ICHIVault vault = ICHIVault(_vault);
        _poolPositions.set(pool, vault, params.yangId);
        emit UnSubscribe(params.yangId, params.chiId, amount0, amount1);
    }

    // views function
    function positions(bytes32 key)
        external
        override
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        PoolPosition.Info memory position = _poolPositions[key];
        (
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = (
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function getShares(uint256 chiId, uint256 amount0Desired, uint256 amount1Desired)
        external
        override
        view
        returns (uint256, uint256, uint256)
    {
        require(_chiManager != address(0), 'prepare chi manager first');
        (
            ,
            ,
            ,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(_chiManager).chi(chiId);

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

    function getAmounts(uint256 yangId, uint256 chiId, address user)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(_chiManager != address(0), 'prepare chi manager first');
        bytes32 key = keccak256(abi.encodePacked(yangId, chiId, user));
        require(_chiPositionSet.contains(key), 'missing chi position');

        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(_chiManager).chi(chiId);
        ICHIVault vault = ICHIVault(_vault);
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        uint256 shares = _chiPositions[key].shares;
        (amount0, amount1) = SharesHelper.calcAmountsFromShares(
                pool,
                vault,
                address(this),
                yangId,
                shares
        );
        emit AmountsFromShares(yangId, chiId, user, amount0, amount1);
    }
}
