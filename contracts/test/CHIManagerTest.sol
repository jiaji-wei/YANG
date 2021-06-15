// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;


import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./CHIVaultTest.sol";
import "../libraries/CHI.sol";
import "../libraries/YangPosition.sol";
import "../interfaces/ICHIManager.sol";
import "../interfaces/ICHIVault.sol";
import "../interfaces/ICHIDepositCallBack.sol";


contract CHIManagerTest is ERC721, ICHIManager, ICHIDepositCallBack
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using YangPosition for mapping(bytes32 => YangPosition.Info);
    using YangPosition for YangPosition.Info;

    address private _yangNFT;
    address private _v3Factory;
    address private _deployer;

    // CHI data
    struct CHIData {
        address operator;
        address pool;
        address vault;
    }

    /// @dev The token ID data
    mapping(uint256 => CHIData) private _chi;

    mapping(bytes32 => YangPosition.Info) public positions;

    uint176 private _nextId = 1;
    uint256 private _tempChiId;
    modifier subscripting(uint256 chiId) {
        _tempChiId = chiId;
        _;
        _tempChiId = 0;
    }

    constructor(address yangNFT, address v3Factory, address deployer)
        ERC721("Test YIN's Uniswap V3 Positions Manager", "TestCHI")
    {
        _yangNFT = yangNFT;
        _v3Factory = v3Factory;
        _deployer = deployer;
    }

    function mint(CHI.MintParams calldata params)
        external
        override
        returns (
            uint256 tokenId,
            address vault
        )
    {
        address uniswapPool = IUniswapV3Factory(_v3Factory).getPool(params.token0, params.token1, params.fee);

        require(uniswapPool != address(0), "Non-existent pool");

        vault = address(new CHIVaultTest(uniswapPool, address(this)));
        _mint(params.recipient, (tokenId = _nextId++));


        _chi[tokenId] = CHIData({
            operator: params.recipient,
            pool: uniswapPool,
            vault: vault
        });

        emit Create(tokenId, uniswapPool, vault, params.vaultFee);
    }

    function chi(uint256 tokenId)
        external
        view
        override
        returns (
            address owner,
            address operator,
            address pool,
            address vault,
            uint256 accruedProtocolFees0,
            uint256 accruedProtocolFees1,
            uint256 fee,
            uint256 totalShares
        )
    {
        CHIData storage _chi_ = _chi[tokenId];
        require(_exists(tokenId), 'Invalid token ID');
        ICHIVault _vault = ICHIVault(_chi_.vault);
        return (
            ownerOf(tokenId),
            _chi_.operator,
            _chi_.pool,
            _chi_.vault,
            _vault.accruedProtocolFees0(),
            _vault.accruedProtocolFees1(),
            _vault.protocolFee(),
            _vault.totalSupply()
        );
    }

    function subscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override subscripting(tokenId) returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        CHIData storage _chi_ = _chi[tokenId];
        (shares, amount0, amount1) = ICHIVault(_chi_.vault).deposit(yangId, amount0Desired, amount1Desired, amount0Min, amount1Min);
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        positions[positionKey].shares = positions[positionKey].shares.add(shares);
    }

    function unsubscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external override returns (uint256 amount0, uint256 amount1)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        YangPosition.Info storage _position = positions[positionKey];
        require(_position.shares >= shares, "s");
        CHIData storage _chi_ = _chi[tokenId];
        (amount0, amount1) = ICHIVault(_chi_.vault).withdraw(yangId, shares, amount0Min, amount1Min, to);
        _position.shares = positions[positionKey].shares.sub(shares);
    }

    function CHIDepositCallback(IERC20 token0, uint256 amount0, IERC20 token1, uint256 amount1) external override {
        _verifyCallback(msg.sender);
        if (amount0 > 0) token0.transferFrom(_yangNFT, msg.sender, amount0);
        if (amount1 > 0) token1.transferFrom(_yangNFT, msg.sender, amount1);
    }

    function _verifyCallback(address caller) internal view {
        CHIData storage _chi_ = _chi[_tempChiId];
        require(_chi_.vault == caller, "callback fail");
    }
}
