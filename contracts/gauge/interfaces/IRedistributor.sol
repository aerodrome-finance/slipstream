// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IRedistributor {
    /**
     * @notice Deposits excess emissions into this contract and records the amount
     * @param _amount The amount of rewards to deposit
     * @dev only callable by a valid gauge registered in the voter
     */
    function deposit(uint256 _amount) external;
}
