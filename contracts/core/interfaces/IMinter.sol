// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

interface IMinter {
    /// @notice Processes emissions and rebases. Callable once per epoch (1 week).
    /// @return _period Start of current epoch.
    function updatePeriod() external returns (uint256 _period);

    function aero() external view returns (address);

    function activePeriod() external view returns (uint256);

    function tailEmissionRate() external view returns (uint256);

    function weekly() external view returns (uint256);
}
