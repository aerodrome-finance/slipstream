// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "contracts/core/interfaces/ICLPool.sol";
import "contracts/core/interfaces/IMinter.sol";
import "contracts/core/interfaces/IVotingEscrow.sol";
import "./interfaces/ICLGaugeFactory.sol";
import "./CLGauge.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract CLGaugeFactory is ICLGaugeFactory {
    /// @inheritdoc ICLGaugeFactory
    uint256 public constant override MAX_BPS = 10_000;
    /// @inheritdoc ICLGaugeFactory
    uint256 public constant override WEEKLY_DECAY = 9_900;
    /// @inheritdoc ICLGaugeFactory
    uint256 public constant override TAIL_START_TIMESTAMP = 1733356800;

    /// @inheritdoc ICLGaugeFactory
    address public immutable override voter;
    /// @inheritdoc ICLGaugeFactory
    address public immutable override minter;
    /// @inheritdoc ICLGaugeFactory
    ICLGaugeFactory public immutable override legacyCLGaugeFactory;
    /// @inheritdoc ICLGaugeFactory
    address public immutable override rewardToken;
    /// @inheritdoc ICLGaugeFactory
    address public immutable override implementation;

    /// @inheritdoc ICLGaugeFactory
    address public override redistributor;
    /// @inheritdoc ICLGaugeFactory
    address public override nft;
    /// @inheritdoc ICLGaugeFactory
    address public override notifyAdmin;
    /// @inheritdoc ICLGaugeFactory
    address public override emissionAdmin;
    /// @inheritdoc ICLGaugeFactory
    uint256 public override defaultCap;
    /// @inheritdoc ICLGaugeFactory
    uint256 public override weeklyEmissions;
    /// @inheritdoc ICLGaugeFactory
    uint256 public override activePeriod;
    /// @inheritdoc ICLGaugeFactory
    mapping(address => bool) public override isGauge;
    /// @dev Emission cap for each gauge
    mapping(address => uint256) internal _emissionCaps;

    address private owner;

    constructor(
        address _voter,
        address _implementation,
        address _emissionAdmin,
        uint256 _defaultCap,
        address _legacyCLGaugeFactory
    ) {
        voter = _voter;
        owner = msg.sender;
        notifyAdmin = msg.sender;
        implementation = _implementation;
        address _minter = IVoter(_voter).minter();
        minter = _minter;
        legacyCLGaugeFactory = ICLGaugeFactory(_legacyCLGaugeFactory);
        rewardToken = address(IMinter(_minter).aero());
        emissionAdmin = _emissionAdmin;
        _setDefaultCap({_defaultCap: _defaultCap});
    }

    /// @inheritdoc ICLGaugeFactory
    function setEmissionAdmin(address _admin) external override {
        require(msg.sender == emissionAdmin, "NA");
        require(_admin != address(0), "ZA");
        emissionAdmin = _admin;
        emit SetEmissionAdmin({_emissionAdmin: _admin});
    }

    /// @inheritdoc ICLGaugeFactory
    function setNotifyAdmin(address _admin) external override {
        require(msg.sender == notifyAdmin, "NA");
        require(_admin != address(0), "ZA");
        notifyAdmin = _admin;
        emit SetNotifyAdmin({_notifyAdmin: _admin});
    }

    /// @inheritdoc ICLGaugeFactory
    function setNonfungiblePositionManager(address _nft) external override {
        require(nft == address(0), "AI");
        require(msg.sender == owner, "NA");
        require(_nft != address(0), "ZA");
        nft = _nft;
        delete owner;
    }

    /// @inheritdoc ICLGaugeFactory
    function setEmissionCap(address _gauge, uint256 _emissionCap) external override {
        require(msg.sender == emissionAdmin, "NA");
        require(_gauge != address(0), "ZA");
        require(_emissionCap <= MAX_BPS, "MC");
        _emissionCaps[_gauge] = _emissionCap;
        emit SetEmissionCap({_gauge: _gauge, _newEmissionCap: _emissionCap});
    }

    /// @inheritdoc ICLGaugeFactory
    function setRedistributor(address _redistributor) external override {
        require(msg.sender == emissionAdmin, "NA");
        require(_redistributor != address(0), "ZA");
        // must transfer team and notify admin permissions before changing this value
        require(redistributor != IVotingEscrow(IVoter(voter).ve()).team(), "ET");
        require(redistributor != legacyCLGaugeFactory.notifyAdmin(), "LNA");

        redistributor = _redistributor;
        emit SetRedistributor({_newRedistributor: _redistributor});
    }

    /// @inheritdoc ICLGaugeFactory
    function setDefaultCap(uint256 _defaultCap) external override {
        require(msg.sender == emissionAdmin, "NA");
        _setDefaultCap({_defaultCap: _defaultCap});
    }

    /// @inheritdoc ICLGaugeFactory
    function emissionCaps(address _gauge) public view override returns (uint256) {
        uint256 emissionCap = _emissionCaps[_gauge];
        return emissionCap == 0 ? defaultCap : emissionCap;
    }

    /// @inheritdoc ICLGaugeFactory
    function createGauge(
        address, /* _forwarder */
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        bool _isPool
    ) external override returns (address _gauge) {
        require(msg.sender == voter, "NV");
        address token0 = ICLPool(_pool).token0();
        address token1 = ICLPool(_pool).token1();
        int24 tickSpacing = ICLPool(_pool).tickSpacing();
        _gauge = Clones.clone({master: implementation});
        ICLGauge(_gauge).initialize({
            _pool: _pool,
            _feesVotingReward: _feesVotingReward,
            _rewardToken: _rewardToken,
            _voter: voter,
            _nft: nft,
            _token0: token0,
            _token1: token1,
            _tickSpacing: tickSpacing,
            _isPool: _isPool
        });
        ICLPool(_pool).setGaugeAndPositionManager({_gauge: _gauge, _nft: nft});
        isGauge[_gauge] = true;
    }

    /// @inheritdoc ICLGaugeFactory
    function calculateMaxEmissions(address _gauge) external override returns (uint256) {
        uint256 _activePeriod = IMinter(minter).activePeriod();
        uint256 maxRate = emissionCaps({_gauge: _gauge});

        if (activePeriod != _activePeriod) {
            uint256 _weeklyEmissions;
            if (_activePeriod < TAIL_START_TIMESTAMP) {
                // @dev Calculate weekly emissions before decay
                _weeklyEmissions = (IMinter(minter).weekly() * MAX_BPS) / WEEKLY_DECAY;
            } else {
                // @dev Calculate tail emissions
                // Tail emissions are slightly inflated since `totalSupply` includes this week's emissions
                // The difference is negligible as weekly emissions are a small percentage of `totalSupply`
                uint256 totalSupply = IERC20(rewardToken).totalSupply();
                _weeklyEmissions = (totalSupply * IMinter(minter).tailEmissionRate()) / MAX_BPS;
            }

            activePeriod = _activePeriod;
            weeklyEmissions = _weeklyEmissions;
            return (_weeklyEmissions * maxRate) / MAX_BPS;
        } else {
            return (weeklyEmissions * maxRate) / MAX_BPS;
        }
    }

    function _setDefaultCap(uint256 _defaultCap) internal {
        require(_defaultCap != 0, "ZDC");
        require(_defaultCap <= MAX_BPS, "MC");
        defaultCap = _defaultCap;
        emit SetDefaultCap({_newDefaultCap: _defaultCap});
    }
}
