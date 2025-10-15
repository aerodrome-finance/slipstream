// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface ICLGaugeFactory {
    event SetNotifyAdmin(address indexed _notifyAdmin);
    event SetEmissionAdmin(address indexed _emissionAdmin);
    event SetDefaultCap(uint256 indexed _newDefaultCap);
    event SetEmissionCap(address indexed _gauge, uint256 _newEmissionCap);
    event SetRedistributor(address indexed _newRedistributor);

    /// @notice Denominator for emission calculations (as basis points)
    function MAX_BPS() external view returns (uint256);

    /// @notice Decay rate of emissions as percentage of `MAX_BPS`
    function WEEKLY_DECAY() external view returns (uint256);

    /// @notice Timestamp of the epoch when tail emissions will start
    function TAIL_START_TIMESTAMP() external view returns (uint256);

    /// @notice Address of the voter contract
    function voter() external view returns (address);

    /// @notice Minter contract used to mint emissions
    function minter() external view returns (address);

    /// @notice The address of the legacy CLGaugeFactory
    /// @dev The legacy CLGaugeFactory that operates concurrently with this gauge factory
    /// @return The address of the legacy gauge factory
    function legacyCLGaugeFactory() external view returns (ICLGaugeFactory);

    /// @notice Reward token supported by this factory
    function rewardToken() external view returns (address);

    /// @notice Address of the gauge implementation contract
    function implementation() external view returns (address);

    /// @notice Address of the NonfungiblePositionManager used to create nfts that gauges will accept
    function nft() external view returns (address);

    /// @notice Administrator that can call `notifyRewardWithoutClaim` on gauges
    function notifyAdmin() external view returns (address);

    /// @notice Administrator that can manage emission caps
    function emissionAdmin() external view returns (address);

    /// @notice Default emission cap set on Gauges
    function defaultCap() external view returns (uint256);

    /// @notice Value of Weekly Emissions for given Epoch
    function weeklyEmissions() external view returns (uint256);

    /// @notice Timestamp of start of epoch that `calculateMaxEmissions()` was last called in
    function activePeriod() external view returns (uint256);

    /// @notice Address of the Redistributor contract to send excess emissions to
    function redistributor() external view returns (address);

    /// @notice Checks if the given address is a gauge created by this factory
    /// @param _gauge The address to check
    /// @return Whether the given address is a gauge created by this factory
    function isGauge(address _gauge) external view returns (bool);

    /// @notice Returns the emission cap of a Gauge
    /// @param _gauge The gauge we are viewing the emission cap of
    /// @return The emission cap of the gauge
    function emissionCaps(address _gauge) external view returns (uint256);

    /// @notice Set emissionAdmin value on gauge factory
    /// @param _admin New administrator that will be able to manage emission caps
    function setEmissionAdmin(address _admin) external;

    /// @notice Set Nonfungible Position Manager
    /// @dev Callable once only on initialize
    /// @param _nft The nonfungible position manager that will manage positions for this Factory
    function setNonfungiblePositionManager(address _nft) external;

    /// @notice Set notifyAdmin value on gauge factory
    /// @param _admin New administrator that will be able to call `notifyRewardWithoutClaim` on gauges.
    function setNotifyAdmin(address _admin) external;

    /// @notice Sets the emission cap for a Gauge
    /// @param _gauge Address of the gauge contract
    /// @param _emissionCap The emission cap to be set
    function setEmissionCap(address _gauge, uint256 _emissionCap) external;

    /// @notice Sets a new redistributor contract
    /// @param _redistributor Address of the new redistributor contract
    /// @dev Only callable by the emission admin
    /// @dev The redistributor permissions (escrow.team or notifyAdmin in legacy gauge factory) should be transferred beforehand.
    /// @dev Will revert if the current redistributor still holds permissions.
    function setRedistributor(address _redistributor) external;

    /// @notice Sets the default emission cap for gauges
    /// @param _defaultCap The default emission cap to be set
    function setDefaultCap(uint256 _defaultCap) external;

    /// @notice Called by the voter contract via factory.createPool
    /// @param _forwarder The address of the forwarder contract
    /// @param _pool The address of the pool
    /// @param _feesVotingReward The address of the feesVotingReward contract
    /// @param _rewardToken The address of the reward token
    /// @param _isPool Whether the attached pool is a real pool or not
    /// @return The address of the created gauge
    function createGauge(
        address _forwarder,
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        bool _isPool
    ) external returns (address);

    /// @notice Calculates max amount of emissions that can be deposited into a gauge
    /// @dev    Max Amount is calculated based on total weekly emissions and `emissionCap` set on gauge
    /// @param _gauge Address of the gauge contract
    function calculateMaxEmissions(address _gauge) external returns (uint256);
}
