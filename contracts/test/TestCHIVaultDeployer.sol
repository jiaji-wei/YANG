// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import '../interfaces/ICHIVaultDeployer.sol';

import './TestCHIVault.sol';

contract TestCHIVaultDeployer is ICHIVaultDeployer {
    address public override owner;
    address public override CHIManager;

    constructor() {
        owner = msg.sender;
    }

    function createVault(
        address uniswapV3pool,
        address manager,
        uint256 fee
    ) external override returns (address pool) {
        require(msg.sender == CHIManager);
        pool = address(new TestCHIVault(uniswapV3pool, manager, fee));
    }

    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function setCHIManager(address _manager) external override {
        require(msg.sender == owner);
        emit CHIManagerChanged(CHIManager, _manager);
        CHIManager = _manager;
    }
}
