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
import "./libraries/SharesHelper.sol";
import "./interfaces/IYangNFTVault.sol";
import "./interfaces/ICHIManager.sol";


contract YangNFTVault is
    IYangNFTVault,
    ReentrancyGuard,
    ERC721
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using CHI for CHI.MintParams;

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

    // chiManager
    address private _chi;

    constructor() ERC721("YANG's Asset Manager", "YANG")
    {
        owner = msg.sender;
    }

    function setCHI(address _chiAddr) external onlyOwner
    {
        _chi = _chiAddr;
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
        address token,
        uint256 amount
    ) external override isAuthorizedForToken(tokenId) nonReentrant
    {
        require(amount > 0, 'deposit need nonzero amount');
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _increasePosition(tokenId, token, amount);
        emit Deposit(tokenId, token, amount, msg.sender);
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

    function withdraw(
        uint256 tokenId,
        address token,
        uint256 amount,
        address recipient
    ) external override isAuthorizedForToken(tokenId) nonReentrant
    {
        require(amount > 0, 'withdraw need nonzero amount');
        _decreasePosition(tokenId, token, amount);
        IERC20(token).safeTransferFrom(address(this), recipient, amount);
    }

    function subscribe(IYangNFTVault.SubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
        nonReentrant
    {
        require(_chi != address(0), 'prepare chi manager first');
        (
            ,
            ,
            address _pool,
            address _vault,
            ,
            ,
            ,
        ) = ICHIManager(_chi).chi(params.chiId);
        require(params.amount0Desired >= params.amount0Min, 'desired amount insufficient');
        require(params.amount1Desired >= params.amount1Min, 'desired amount insufficient');
        (
            uint256 share,
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(_chi).subscribe(
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
        } else {
            _chiPositionSet.add(key);
            _chiPositions[key] = ChiPosition({
                pool: _pool,
                vault: _vault,
                shares: share
            });
        }

        emit Subscribe(params.yangId, params.chiId, share);
    }

    function unsubscribe(IYangNFTVault.UnSubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
        nonReentrant
    {
        require(_chi != address(0), 'prepare chi manager first');
        (
            ,
            ,
            address _pool,
            ,
            ,
            ,
            ,
        ) = ICHIManager(_chi).chi(params.chiId);
        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId, msg.sender));
        require(_chiPositionSet.contains(key), 'missing chi position');

        ChiPosition storage position = _chiPositions[key];
        require(position.shares >= params.shares, 'insufficient shares');
        (
            uint256 amount0,
            uint256 amount1
        ) = ICHIManager(_chi).unsubscribe(
                params.yangId,
                params.chiId,
                params.shares,
                params.amount0Min,
                params.amount1Min,
                params.recipient
            );
        position.shares = position.shares.sub(params.shares);

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        _increasePosition(params.yangId, pool.token0(), amount0);
        _increasePosition(params.yangId, pool.token1(), amount1);

        emit UnSubscribe(params.yangId, params.chiId, amount0, amount1);
    }
}
