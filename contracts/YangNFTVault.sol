// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './libraries/PoolPosition.sol';
import './libraries/YangPosition.sol';
import './libraries/SharesHelper.sol';
import './interfaces/IYangNFTVault.sol';
import './interfaces/ICHIManager.sol';
import './interfaces/ICHIVault.sol';

contract YangNFTVault is IYangNFTVault, ReentrancyGuard, ERC721 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PoolPosition for mapping(bytes32 => PoolPosition.Info);
    using PoolPosition for PoolPosition.Info;
    using YangPosition for mapping(bytes32 => YangPosition.Info);
    using YangPosition for YangPosition.Info;

    // owner
    address public owner;
    address private chiManager;

    modifier onlyOwner {
        require(msg.sender == owner, 'only owner');
        _;
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'not approved');
        _;
    }

    // nft and Yang tokenId
    uint256 private _nextId = 1;
    mapping(address => uint256) private _usersMap;

    // yangPosition
    mapping(bytes32 => YangPosition.Info) private _positions;

    // poolPosition
    mapping(bytes32 => PoolPosition.Info) private _poolPositions;

    // vaults
    mapping(bytes32 => uint256) private _vaults;

    constructor() ERC721('YIN Asset Manager Vault', 'YANG') {
        owner = msg.sender;
    }

    function setCHIManager(address _chiManager) external override onlyOwner {
        chiManager = _chiManager;
    }

    function mint(address recipient) external override returns (uint256 tokenId) {
        require(_usersMap[recipient] == 0, 'OO');
        // _mint function check tokenId existence
        _mint(recipient, (tokenId = _nextId++));
        _usersMap[recipient] = tokenId;

        emit MintYangNFT(recipient, tokenId);
    }

    function deposit(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) public override {
        require(amount0 > 0, 'NZ');
        require(amount1 > 0, 'NZ');
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
    }

    function withdraw(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) public override {

        uint256 yangId = getTokenId(msg.sender);
        if (amount0 > 0) {
            bytes32 key0 = keccak256(abi.encodePacked(yangId, token0));
            _vaults[key0] = _vaults[key0].sub(amount0);
            IERC20(token0).safeTransfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            bytes32 key1 = keccak256(abi.encodePacked(yangId, token1));
            _vaults[key1] = _vaults[key1].sub(amount1);
            IERC20(token1).safeTransfer(msg.sender, amount1);
        }
    }

    function _subscribe(
        address token0,
        address token1,
        IYangNFTVault.SubscribeParam memory params
    )
        internal
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 shares
        )
    {
        IERC20(token0).safeApprove(chiManager, params.amount0Desired);
        IERC20(token1).safeApprove(chiManager, params.amount1Desired);

        (shares, amount0, amount1) = ICHIManager(chiManager).subscribe(
            params.yangId,
            params.chiId,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Min,
            params.amount1Min
        );

        if (params.amount0Desired - amount0 > 0) {
            bytes32 key0 = keccak256(abi.encodePacked(params.yangId, token0));
            _vaults[key0] = _vaults[key0].add(amount0);
        }

        if (params.amount1Desired - amount1 > 0) {
            bytes32 key1 = keccak256(abi.encodePacked(params.yangId, token1));
            _vaults[key1] = _vaults[key1].add(amount1);
        }

        IERC20(token0).safeApprove(chiManager, 0);
        IERC20(token1).safeApprove(chiManager, 0);
    }

    function subscribe(IYangNFTVault.SubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
        nonReentrant
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 shares
        )
    {
        require(chiManager != address(0), 'CHI');
        (, , address _pool, address _vault, , , , ) = ICHIManager(chiManager).chi(params.chiId);

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        address token0 = pool.token0();
        address token1 = pool.token1();

        // deposit valut to yangNFT and then to chi
        deposit(token0, params.amount0Desired, token1, params.amount1Desired);

        (amount0, amount1, shares) = _subscribe(token0, token1, params);

        YangPosition.Info storage position = _positions.get(params.yangId, params.chiId);
        position.amount0 = position.amount0.add(amount0);
        position.amount1 = position.amount1.add(amount1);
        position.shares = position.shares.add(shares);

        _poolPositions.set(pool, ICHIVault(_vault), params.yangId);
        emit Subscribe(params.yangId, params.chiId, shares);
    }

    function unsubscribe(IYangNFTVault.UnSubscribeParam memory params)
        external
        override
        isAuthorizedForToken(params.yangId)
    {
        require(chiManager != address(0), 'CHI');
        (, , address _pool, address _vault, , , , ) = ICHIManager(chiManager).chi(params.chiId);

        bytes32 key = keccak256(abi.encodePacked(params.yangId, params.chiId));
        require(_positions[key].shares >= params.shares, 'insufficient shares');

        (uint256 amount0, uint256 amount1) = ICHIManager(chiManager).unsubscribe(
            params.yangId,
            params.chiId,
            params.shares,
            params.amount0Min,
            params.amount1Min
        );

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        if (amount0 > 0) {
            bytes32 key0 = keccak256(abi.encodePacked(params.yangId, pool.token0()));
            _vaults[key0] = _vaults[key0].add(amount0);
        }
        if (amount1 > 0) {
            bytes32 key1 = keccak256(abi.encodePacked(params.yangId, pool.token1()));
            _vaults[key1] = _vaults[key1].add(amount1);
        }

        YangPosition.Info storage position = _positions.get(params.yangId, params.chiId);
        position.shares = position.shares.sub(params.shares);
        position.amount0 = position.amount0 > amount0 ? position.amount0.sub(amount0) : 0;
        position.amount1 = position.amount1 > amount1 ? position.amount1.sub(amount1) : 0;

        ICHIVault vault = ICHIVault(_vault);
        _poolPositions.set(pool, vault, params.yangId);
        emit UnSubscribe(params.yangId, params.chiId, amount0, amount1);
    }

    // views function

    function yangPositions(uint256 yangId, uint256 chiId)
        external
        view
        override
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 shares
        )
    {
        YangPosition.Info memory position = _positions[keccak256(abi.encodePacked(yangId, chiId))];
        amount0 = position.amount0;
        amount1 = position.amount1;
        shares = position.shares;
    }

    function poolPositions(bytes32 key)
        external
        view
        override
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        PoolPosition.Info memory position = _poolPositions[key];
        (liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, tokensOwed0, tokensOwed1) = (
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function getTokenId(address recipient) public view override returns (uint256) {
        return _usersMap[recipient];
    }

    function vaults(address token) external view override returns (uint256) {
        uint256 yangId = getTokenId(msg.sender);
        return _vaults[keccak256(abi.encodePacked(yangId, token))];
    }

    function getCHITotalAmounts(uint256 chiId) external view override returns (uint256 amount0, uint256 amount1) {
        require(chiManager != address(0), 'CHI');
        (, , , address _vault, , , , ) = ICHIManager(chiManager).chi(chiId);
        (amount0, amount1) = ICHIVault(_vault).getTotalAmounts();
    }

    function getCHIAccruedFees(uint256 chiId) external view override returns (uint256 fee0, uint256 fee1) {
        require(chiManager != address(0), 'CHI');
        (, , , address _vault, , , , ) = ICHIManager(chiManager).chi(chiId);
        fee0 = ICHIVault(_vault).accruedProtocolFees0();
        fee1 = ICHIVault(_vault).accruedProtocolFees1();
    }

    function getShares(
        uint256 chiId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view override returns (uint256) {
        require(chiManager != address(0), 'CHI');
        (, , , address _vault, , , , ) = ICHIManager(chiManager).chi(chiId);
        (uint256 shares, , ) = SharesHelper.getSharesAndAmounts(_vault, amount0Desired, amount1Desired);
        return shares;
    }

    function getAmounts(uint256 yangId, uint256 chiId)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(chiManager != address(0), 'CHI');
        bytes32 key = keccak256(abi.encodePacked(yangId, chiId));
        YangPosition.Info memory position = _positions[key];
        if (position.shares > 0) {
            (, , address _pool, address _vault, , , , ) = ICHIManager(chiManager).chi(chiId);
            (amount0, amount1) = SharesHelper.getAmounts(_pool, _vault, yangId, position.shares);
        }
    }
}
