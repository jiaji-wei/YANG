// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;


import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "../interfaces/ICHIVault.sol";
import "../interfaces/ICHIManager.sol";
import "../interfaces/ICHIVaultDeployer.sol";

import "../libraries/CHI.sol";
import "../libraries/YangPosition.sol";


contract TestCHIManager is ERC721, ICHIManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using YangPosition for mapping(bytes32 => YangPosition.Info);
    using YangPosition for YangPosition.Info;
    // CHI ID
    uint176 private _nextId = 1;

    /// YANG position
    mapping(bytes32 => YangPosition.Info) public positions;

    // CHI data
    struct CHIData {
        address operator;
        address pool;
        address vault;
    }

    /// @dev The token ID data
    mapping(uint256 => CHIData) private _chi;

    address public v3Factory;
    address public yangNFT;
    address public deployer;
    address public chigov;
    address public nextgov;

    constructor(
        address _v3Factory,
        address _yangNFT,
        address _deployer,
        address _gov
    ) ERC721("YIN's Uniswap V3 Positions Manager", 'CHI') {
        v3Factory = _v3Factory;
        yangNFT = _yangNFT;
        deployer = _deployer;
        chigov = _gov;
    }

    modifier onlyYANG {
        require(msg.sender == address(yangNFT), 'y');
        _;
    }

    modifier onlyGov {
        require(msg.sender == chigov, 'gov');
        _;
    }

    function acceptGovernance() external {
        require(msg.sender == nextgov, 'next gov');
        chigov = msg.sender;
        nextgov = address(0);
    }

    function setGovernance(address _governance) external onlyGov {
        nextgov = _governance;
    }

    uint256 private _tempChiId;
    modifier subscripting(uint256 chiId) {
        _tempChiId = chiId;
        _;
        _tempChiId = 0;
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

    function mint(MintParams calldata params) external override onlyGov returns (uint256 tokenId, address vault) {
        address uniswapPool = IUniswapV3Factory(v3Factory).getPool(params.token0, params.token1, params.fee);

        require(uniswapPool != address(0), 'Non-existent pool');

        vault = ICHIVaultDeployer(deployer).createVault(uniswapPool, address(this), params.vaultFee);
        _mint(params.recipient, (tokenId = _nextId++));

        _chi[tokenId] = CHIData({operator: params.recipient, pool: uniswapPool, vault: vault});

        emit Create(tokenId, uniswapPool, vault, params.vaultFee);
    }

    function subscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        onlyYANG
        subscripting(tokenId)
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        CHIData storage _chi_ = _chi[tokenId];
        (shares, amount0, amount1) = ICHIVault(_chi_.vault).deposit(
            yangId,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        positions[positionKey].shares = positions[positionKey].shares.add(shares);
    }

    function unsubscribe(
        uint256 yangId,
        uint256 tokenId,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override onlyYANG returns (uint256 amount0, uint256 amount1) {
        bytes32 positionKey = keccak256(abi.encodePacked(yangId, tokenId));
        YangPosition.Info storage _position = positions[positionKey];
        require(_position.shares >= shares, 's');
        CHIData storage _chi_ = _chi[tokenId];
        (, , amount0, amount1) = ICHIVault(_chi_.vault).withdraw(yangId, shares, amount0Min, amount1Min, yangNFT);
        _position.shares = positions[positionKey].shares.sub(shares);
    }

    function CHIDepositCallback(
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1
    ) external override {
        _verifyCallback(msg.sender);
        if (amount0 > 0) token0.transferFrom(yangNFT, msg.sender, amount0);
        if (amount1 > 0) token1.transferFrom(yangNFT, msg.sender, amount1);
    }

    function _verifyCallback(address caller) internal view {
        CHIData storage _chi_ = _chi[_tempChiId];
        require(_chi_.vault == caller, 'callback fail');
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    function addRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) external override isAuthorizedForToken(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).addRange(tickLower, tickUpper);
    }

    function removeRange(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) external override isAuthorizedForToken(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).removeRange(tickLower, tickUpper);
    }

    function collectProtocol(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        address to
    ) external override isAuthorizedForToken(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).collectProtocol(amount0, amount1, to);
    }

    function addLiquidityToPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external override isAuthorizedForToken(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).addLiquidityToPosition(rangeIndex, amount0Desired, amount1Desired);
    }

    function removeLiquidityFromPosition(
        uint256 tokenId,
        uint256 rangeIndex,
        uint128 liquidity
    ) external override isAuthorizedForToken(tokenId) {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).removeLiquidityFromPosition(rangeIndex, liquidity);
    }

    function removeAllLiquidityFromPosition(uint256 tokenId, uint256 rangeIndex)
        external
        override
        isAuthorizedForToken(tokenId)
    {
        CHIData storage _chi_ = _chi[tokenId];
        ICHIVault(_chi_.vault).removeAllLiquidityFromPosition(rangeIndex);
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _chi[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
