// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import {IVoter} from "contracts/core/interfaces/IVoter.sol";

/**
 * @title IRedistributor
 * @notice Interface of emissions redistributor
 */
interface IRedistributor {
    event Deposited(address indexed gauge, address indexed to, uint256 amount);

    /**
     * @notice Deposits excess emissions into the redistributor
     * @param _amount The amount of rewards to deposit
     * @dev Only callable by a valid gauge registered in the voter
     * @dev Assumes this function can only be called once by each gauge per epoch
     */
    function deposit(uint256 _amount) external;

    /**
     * @notice The address of the voter contract
     * @return Address of the voter
     */
    function voter() external view returns (IVoter);

    /**
     * @notice The address of the minter contract, used to mint emissions
     * @return Address of the minter
     */
    function minter() external view returns (address);

    /**
     * @notice The address of the voting escrow contract
     * @return Address of the voting escrow
     */
    function escrow() external view returns (address);

    /**
     * @notice The address of the CL gauge factory with emission cap support
     * @return Address of the gauge factory
     */
    function gaugeFactory() external view returns (address);

    /**
     * @notice The address of the reward token distributed by gauges
     * @return Address of the reward token
     */
    function rewardToken() external view returns (address);

    /**
     * @notice The total voting weight for a given epoch
     * @param _epochStart The start of the epoch to fetch the voting weight for
     * @return The total voting weight for the epoch
     */
    function totalWeight(uint256 _epochStart) external view returns (uint256);

    /**
     * @notice The amount of emissions to be redistributed in a given epoch
     * @param _epochStart The start of the epoch to fetch the emissions for
     * @return The emissions to be redistributed in the given epoch
     */
    function totalEmissions(uint256 _epochStart) external view returns (uint256);

    /**
     * @notice Checks if a gauge is excluded for redistributes in the given epoch
     * @param _epochStart The start of the epoch to check
     * @param _gauge The address of the gauge to check for exclusion
     * @return Whether the gauge is excluded for redistributes in the given epoch
     */
    function isExcluded(uint256 _epochStart, address _gauge) external view returns (bool);
}
