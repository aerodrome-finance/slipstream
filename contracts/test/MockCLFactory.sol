// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

/// @dev Mock CLFactory to be used in CLFactory V2, to simulate permissionless pool creation
contract MockCLFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool) {}
}
