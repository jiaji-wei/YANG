// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./interfaces/IYANGManager.sol";
import "./interfaces/IYANGVault.sol";
import "./interfaces/IYANGCallBack.sol";
import "./interfaces/ICHIManager.sol";

contract YANGVault is IYANGVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    IYANGManager private yangManager;
    ICHIManager private chiManager;
    EnumerableSet.Bytes32Set private _poolSet;
    EnumerableSet.AddressSet private _tokenSet;

    struct Position {
        uint256 yangId;
        address user;
        address token;
        uint256 balance;
    }
    mapping(bytes32 => Position) private _positions;
    EnumerableSet.Bytes32Set private _positionKeySet;

    struct Pool {
        address token0;
        address token1;
    }
    uint256 private _vaultFee;
    mapping(bytes32 => Pool) private _poolMap;

    modifier onlyYangManager {
        require(msg.sender == address(yangManager));
        _;
    }

    constructor(address _chiManager, address _yangManager) {
        yangManager = IYANGManager(_yangManager);
        chiManager = ICHIManager(_chiManager);
    }

    function getVaultFee() external override view returns (uint256) {
        return _vaultFee;
    }

    function setVaultFee(uint256 fee)
        external
        override
        onlyYangManager
    {
        _vaultFee = fee;
    }

    function addPool(address token0, address token1)
        external
        override
        onlyYangManager
    {
        _tokenSet.add(token0);
        _tokenSet.add(token1);
        bytes32 tokenKey = keccak256(abi.encodePacked(token0, token1));
        if (!_poolSet.contains(tokenKey)) {
            _poolSet.add(tokenKey);
            _poolMap[tokenKey] = Pool({token0: token0, token1: token1});
        }
    }

    function poolLength() external override view returns (uint256 length)
    {
        length = _poolSet.length();
    }

    function tokenLength() external override view returns (uint256 length)
    {
        length = _tokenSet.length();
    }

    function showPoolAt(uint256 index)
        external
        override
        view
        returns (address token0, address token1)
    {
        require(index < _poolSet.length(), "Exceed poolSet length");
        bytes32 key = _poolSet.at(index);
        Pool storage pool = _poolMap[key];
        (token0, token1) = (pool.token0, pool.token1);
    }

    function showTokenAt(uint256 index)
        external
        override
        view
        returns (address token)
    {
        require(index < _tokenSet.length(), "Exceed tokenSet length");
        token = _tokenSet.at(index);
    }

    function _addPosition(
        uint256 yangId,
        address user,
        address token,
        uint256 amount
    ) internal
    {
        bytes32 key = keccak256(abi.encodePacked(yangId, user, token));
        if (_positionKeySet.contains(key)) {
            Position storage position = _positions[key];
            position.balance.add(amount);
        } else {
            _positionKeySet.add(key);
            _positions[key] = Position({
                yangId: yangId,
                user: user,
                token: token,
                balance: amount
            });
        }
    }

    // Deposit
    function deposit(
        uint256 yangId,
        address user,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    )
        external
        override
        nonReentrant
        onlyYangManager
    {
        // Pull in tokens from sender
        IYANGCallBack(msg.sender).DepositCallBack(
            user,
            IERC20(token0),
            amount0,
            IERC20(token1),
            amount1
        );

        if (amount0 > 0) _addPosition(yangId, user, token0, amount0);
        if (amount1 > 0) _addPosition(yangId, user, token1, amount1);
        emit Deposit(yangId, amount0, amount1);
    }

    function _burnPosition(
        uint256 yangId,
        address user,
        address token,
        uint256 amount
    ) internal
    {
        bytes32 key = keccak256(abi.encodePacked(yangId, user, token));
        require(_positionKeySet.contains(key), "Missing position");
        Position storage position = _positions[key];
        position.balance.sub(amount);
    }

    // Withdraw
    function withdraw(
        uint256 yangId,
        address user,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    )
        external
        override
        nonReentrant
        onlyYangManager
    {
        // Push tokens to sender
        if (amount0 > 0) _burnPosition(yangId, user, token0, amount0);
        if (amount1 > 0) _burnPosition(yangId, user, token1, amount1);
        IYANGCallBack(msg.sender).WithdrawCallBack(
            user,
            IERC20(token0),
            amount0,
            IERC20(token1),
            amount1
        );
        emit Withdraw(yangId, user, amount0, amount1);
    }
}
