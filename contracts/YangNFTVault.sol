// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./libraries/PoolPosition.sol";
import "./interfaces/IYangNFTVault.sol";
import "./interfaces/ICHIManager.sol";
import "./interfaces/ICHIVault.sol";
import "./interfaces/IYangView.sol";


contract YangNFTVault is
    IYangNFTVault,
    ReentrancyGuard,
    ERC721
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PoolPosition for mapping(bytes32 => PoolPosition.Info);
    using PoolPosition for PoolPosition.Info;

    // owner
    address public owner;
    modifier onlyOwner {
        require(msg.sender == owner, 'only owner');
        _;
    }

    // nft and Yang tokenId

    uint256 private _nextId = 1;
    mapping(bytes32 => bool) private _userExists;
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'not approved');
        _;
    }

    // yangPosition
    mapping(bytes32 => uint256) private _yangPositions;

    // chiPosition
    mapping(bytes32 => uint256) private _chiPositions;

    // poolPosition
    mapping(bytes32 => PoolPosition.Info) private _poolPositions;

    // chiManager
    address private chiManager;

    // yangView
    address public yangView;

    constructor() ERC721("YANG's Asset Manager", "YANG")
    {
        owner = msg.sender;
    }

    function setCHIManager(address _chiManager) external override onlyOwner
    {
        chiManager = _chiManager;
    }

    function setYangView(address _yangView) external override onlyOwner
    {
        yangView = _yangView;
    }

    function mint(address recipient)
        external
        override
        returns (uint256 tokenId)
    {
        bytes32 key = keccak256(abi.encodePacked(recipient, (tokenId = _nextId++)));
        require(_userExists[key] == false, 'OO');

        // _mint function check tokenId existence
        _mint(recipient, tokenId);
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
        require(amount0 > 0, 'NZ');
        require(amount1 > 0, 'NZ');
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
        _yangPositions[key] = _yangPositions[key].add(amount);
    }

    function _decreasePosition(uint256 tokenId, address token, uint256 amount) internal
    {
        bytes32 key = keccak256(abi.encodePacked(tokenId, msg.sender, token));
        require(_yangPositions[key] >= amount, 'insufficient balance');
        _yangPositions[key] = _yangPositions[key].sub(amount);
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
        require(amount0 > 0, 'NZ');
        require(amount1 > 0, 'NZ');
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
        require(chiManager != address(0), 'CHI');
        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(chiManager).chi(params.chiId);

        IERC20(pool.token0()).safeApprove(chiManager, params.amount0Desired);
        IERC20(pool.token1()).safeApprove(chiManager, params.amount1Desired);

        (
            uint256 share,
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(chiManager).subscribe(
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

        IERC20(pool.token0()).safeApprove(chiManager, 0);
        IERC20(pool.token1()).safeApprove(chiManager, 0);

        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId, msg.sender));
        _chiPositions[key].add(share);

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
        require(chiManager != address(0), 'CHI');
        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(chiManager).chi(params.chiId);

        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId, msg.sender));
        require(_chiPositions[key] >= params.shares, 'insufficient shares');
        (
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(chiManager).unsubscribe(
                params.yangId,
                params.chiId,
                params.shares,
                params.amount0Min,
                params.amount1Min,
                address(this)
            );
        _chiPositions[key] = _chiPositions[key].sub(params.shares);

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
        returns (uint256)
    {
        require(chiManager != address(0), 'CHI');
        (
            ,
            ,
            ,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(chiManager).chi(chiId);
        (uint256 shares,,) = IYangView(yangView).getSharesAndAmounts(_vault, amount0Desired, amount1Desired);
        return shares;
    }

    function getAmounts(uint256 yangId, uint256 chiId, address user)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(chiManager != address(0), 'CHI');
        bytes32 key = keccak256(abi.encodePacked(yangId, chiId, user));
        if (_chiPositions[key] > 0) {
            (
                ,
                ,
                address _pool,
                address _vault,
                ,
                ,
                ,
            ) = ICHIManager(chiManager).chi(chiId);
            (amount0, amount1) = IYangView(yangView).getAmounts(_pool, _vault, yangId, _chiPositions[key]);
        }
    }
}
