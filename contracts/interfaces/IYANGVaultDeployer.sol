// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface IYANGVaultDeployer {
    function ShowOwner() external view returns (address);
    function ShowManager() external view returns (address);
    function setOwner(address _owner) external;
    function setYangManager(address _manager) external;
    function createVault(address _manager) external returns (address);

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event YangManagerChanged(address indexed oldManager, address indexed newManager);
    event CreateYangVault(address indexed chiManager, address indexed yangManager);
}
