// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "./YANGVault.sol";
import "./interfaces/IYANGVaultDeployer";

contract YANGVaultDeployer is IYANGVaultDeployer {
    address public owner;
    address public manager;

    constructor() {
        owner = msg.sender;
    }

    function ShowOwner() external override views returns (address)
    {
        return owner;
    }

    function ShowManager() external override views returns (address)
    {
        return manager;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only Owner");
        _;
    }

    modifier onlyManager {
        require(msg.sender == manager, "Only Manager");
        _;
    }

    function setOwner(address _owner)
        external
        override
        onlyOwner
    {
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function setYangManger(address _manager)
        external
        override
        onlyOwner
    {
        emit YangManagerChanged(manager, _manager);
        manager = _manager;
    }

    function createVault(address chiManager)
        external
        override
        onlyManager
        returns (address vault)
    {
        vault = address(new YANGVault(chiManager, msg.sender));
        emit CreateYangVault(chiManager, msg.sender);
    }
}
