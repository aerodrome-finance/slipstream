// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import {IVoter} from "contracts/core/interfaces/IVoter.sol";

/**
 * @title IRedistributor
 * @notice Interface of emissions redistributor
 */
interface IRedistributor {
    event Redistributed(address indexed sender, address indexed gauge, uint256 amount);
    event Deposited(address indexed gauge, address indexed to, uint256 amount);
    event NotifyRewardWithoutClaim(address indexed gauge, uint256 amount);
    event SetArtProxy(address indexed proxy);
    event ToggleSplit(address indexed account, bool indexed enabled);
    event PermissionsTransferred(address indexed redistributor, address indexed newRedistributor);
    event SetUpkeepManager(address indexed upkeepManager);
    event SetKeeper(address indexed keeper);

    /**
     * @notice Deposits excess emissions into the redistributor
     * @param _amount The amount of rewards to deposit
     * @dev Only callable by a valid gauge registered in the voter
     * @dev Assumes this function can only be called once by each gauge per epoch
     */
    function deposit(uint256 _amount) external;

    /**
     * @notice Redistributes the emissions to the given gauges according to their voting weight
     * @param _gauges The array of gauge addresses to redistribute emissions to
     * @dev Only callable by keepers registered in the UpkeepManager or the keeper
     */
    function redistribute(address[] memory _gauges) external;

    /**
     * @notice Redistributes the emissions to the gauges in the given index range according to their voting weight
     * @param _start The index of the first pool whose gauge emissions will be distributed to (inclusive)
     * @param _end The index of the last gauge's pool (exclusive)
     * @dev Only callable by keepers registered in the UpkeepManager or the keeper
     */
    function redistribute(uint256 _start, uint256 _end) external;

    /**
     * @notice Notifies the given gauge of rewards without distributing its fees.
     * @param _gauge The address of the gauge to give rewards to
     * @param _amount The amount of rewards to give to the gauge
     * @dev Should pull funds from the caller and call gauge.notifyRewardWithoutClaim
     * @dev Only callable by the owner
     */
    function notifyRewardWithoutClaim(address _gauge, uint256 _amount) external;

    /**
     * @notice Sets the UpkeepManager contract to manage keepers
     * @param _upkeepManager The address to be set as UpkeepManager
     * @dev Only callable by the owner
     */
    function setUpkeepManager(address _upkeepManager) external;

    /**
     * @notice Sets the keeper address
     * @param _keeper The address to be set as keeper
     * @dev Only callable by the owner
     */
    function setKeeper(address _keeper) external;

    /**
     * @notice Sets a new ArtProxy in the VotingEscrow
     * @param _proxy The address to be set as ArtProxy
     * @dev Calls VotingEscrow.setArtProxy
     * @dev Only callable by the owner
     */
    function setArtProxy(address _proxy) external;

    /**
     * @notice Toggle split for a specific address in the VotingEscrow
     * @param _account Address to toggle split permissions
     * @param _bool True to allow, false to disallow
     * @dev Toggle split for address(0) to enable or disable for all.
     * @dev Calls VotingEscrow.toggleSplit
     * @dev Only callable by the owner
     */
    function toggleSplit(address _account, bool _bool) external;

    /**
     * @notice Transfers the redistributor permissions (escrow.team and notifyAdmin in legacy gauge factory) to the given address.
     * @param _newRedistributor The redistributor to which the permissions will be transferred to
     * @dev only callable by the redistributor owner
     */
    function transferPermissions(address _newRedistributor) external;

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
     * @notice The address of the upkeep manager used to register and validate authorized automation upkeeps
     * @return Address of the upkeep manager
     */
    function upkeepManager() external view returns (address);

    /**
     * @notice The address of the keeper
     * @return Address of the keeper
     */
    function keeper() external view returns (address);

    /**
     * @notice Timestamp of start of epoch that `redistribute()` was last called in
     * @return The epoch start timestamp of the last redistribution
     */
    function activePeriod() external view returns (uint256);

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

    /**
     * @notice Checks if a gauge received its redistribute in the given epoch
     * @param _epochStart The start of the epoch to check
     * @param _gauge The address of the gauge to check for redistribution
     * @return Whether the gauge received its redistribute in the given epoch
     */
    function isRedistributed(uint256 _epochStart, address _gauge) external view returns (bool);
}
