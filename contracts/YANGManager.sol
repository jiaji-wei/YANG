// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;


import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libraries/CHI.sol"
import "./interfaces/IYANGVault.sol";
import "./interfaces/IYANGCallBack.sol";

contract YANGManager is
    IYANGManager,
    IYANGDepositCallBack,
    ReentrancyGuard,
    ERC721,
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using CHI for CHI.MintParams;

    # GrandMaster Addresses address private chiManager;
    address private deployer;
    address private vault;

    # NFT Token and YANG ID
    mapping(address => uint256) private _userTokenTracker;
    mapping(bytes32 => boolean) private _userExists;
    Counters.Counter private _tokenIdTracker;

    # Modifier
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    modifier onlyGrandMaster {
        require(msg.sender == chiManager || msg.sender == deployer, 'Failed');
        _;
    }

    constructor(
        address _chiManager,
        address _deployer
    ) ERC721("YANG's Asset Manager", "YANG")
    {
        chiManager = _chiManager;
        deployer = _deployer;
        vault = IYANGDeployer(deployer).createVault(chiManager);
    }

    function mint(address recipient)
        external
        override
        returns (uint256 tokenId) {
        tokenId = _tokenIdTracker.current();
        bytes32 key = keccak256(abi.encodePacked(recipient, token));
        require(_userExists[key] == false, "Alread exists");

        # _mint function check tokenId existence
        _mint(recipient, tokenId);
        _tokenIdTracker.increment();
        _userTokenTracker[recipient] = tokenId;
        _userExists[tokenKey] = true;

        emit CreateNFT(recipient, tokenId);
    }

    function addPool(address token0, address token1)
        external
        override
        onlyGrandMaster
    {
        IYANGVault(vault).addPool(token0, token1);
    }

    function DepositCallBack(
        address user,
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1
    ) external override
    {
        require(msg.sender == vault, "Deposit callback failed");
        if (amount0 > 0) token0.transferFrom(user, msg.sender, amount0);
        if (amount1 > 0) token1.transferFrom(user, msg.sender. amount1);
    }

    function WithdrawCallBack(
        address user,
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1
    ) external override
    {
        require(msg.sender == vault, "Withdraw callback failed");
        if (amount0 > 0) token0.transferFrom(msg.sender, user, amount0);
        if (amount1 > 0) token1.transferFrom(msg.sender, user, amount1);
    }

    function deposit(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external override isAuthorizedForToken(tokenId)
    {
        IYANGVault(vault).deposit(tokenId, msg.sender, token0, amount0, token1, amount1);
    }

    function withdraw(
        uint256 tokenId,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external override isAuthorizedForToken(tokenId)
    {
        IYANGVault(vault).withdraw(tokenId, msg.sender, token0, amount0, token1, amount1);
    }
}
