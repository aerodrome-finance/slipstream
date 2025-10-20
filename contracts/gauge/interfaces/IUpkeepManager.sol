// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IUpkeepManager {
    /**
     * @notice Checks if a given address is a registered automation upkeep
     * @param _account The address to check
     * @return Whether the address is an authorized automation upkeep
     */
    function isUpkeep(address _account) external view returns (bool);
}
