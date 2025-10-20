pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import {TestERC20CustomDecimals} from "./mocks/TestERC20CustomDecimals.sol";

import {CLFactory} from "contracts/core/CLFactory.sol";
import {ICLPool, CLPool} from "contracts/core/CLPool.sol";
import {NonfungibleTokenPositionDescriptor} from "contracts/periphery/NonfungibleTokenPositionDescriptor.sol";
import {
    INonfungiblePositionManager, NonfungiblePositionManager
} from "contracts/periphery/NonfungiblePositionManager.sol";
import {ICLGauge, CLGauge} from "contracts/gauge/CLGauge.sol";
import {CLGaugeFactory} from "contracts/gauge/CLGaugeFactory.sol";
import {MockCLGaugeFactory} from "contracts/test/MockCLGaugeFactory.sol";
import {IUpkeepManager, MockUpkeepManager} from "contracts/test/MockUpkeepManager.sol";
import {IRedistributor, Redistributor} from "contracts/gauge/Redistributor.sol";
import {MockWETH} from "contracts/test/MockWETH.sol";
import {MockCLFactory} from "contracts/test/MockCLFactory.sol";
import {IVoter, MockVoter} from "contracts/test/MockVoter.sol";
import {MockMinter} from "contracts/test/MockMinter.sol";
import {IVotingEscrow, MockVotingEscrow} from "contracts/test/MockVotingEscrow.sol";
import {IFactoryRegistry, MockFactoryRegistry} from "contracts/test/MockFactoryRegistry.sol";
import {IVotingRewardsFactory, MockVotingRewardsFactory} from "contracts/test/MockVotingRewardsFactory.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Constants} from "./utils/Constants.sol";
import {Events} from "./utils/Events.sol";
import {PoolUtils} from "./utils/PoolUtils.sol";
import {Users} from "./utils/Users.sol";
import {SafeCast} from "contracts/gauge/libraries/SafeCast.sol";
import {ProtocolTimeLibrary} from "contracts/libraries/ProtocolTimeLibrary.sol";
import {TestCLCallee} from "contracts/core/test/TestCLCallee.sol";
import {NFTManagerCallee} from "contracts/periphery/test/NFTManagerCallee.sol";
import {CustomUnstakedFeeModule} from "contracts/core/fees/CustomUnstakedFeeModule.sol";
import {CustomSwapFeeModule} from "contracts/core/fees/CustomSwapFeeModule.sol";
import {DynamicSwapFeeModule} from "contracts/core/fees/DynamicSwapFeeModule.sol";
import {IMinter} from "contracts/core/interfaces/IMinter.sol";

abstract contract BaseFixture is Test, Constants, Events, PoolUtils {
    CLFactory public poolFactory;
    CLFactory public legacyPoolFactory;
    CLPool public poolImplementation;
    NonfungibleTokenPositionDescriptor public nftDescriptor;
    NonfungiblePositionManager public nft;
    CLGaugeFactory public gaugeFactory;
    CLGaugeFactory public legacyGaugeFactory;
    CLGauge public gaugeImplementation;
    Redistributor public redistributor;

    /// @dev mocks
    IFactoryRegistry public factoryRegistry;
    IVoter public voter;
    IVotingEscrow public escrow;
    IMinter public minter;
    IERC20 public weth;
    IVotingRewardsFactory public votingRewardsFactory;
    IUpkeepManager public upkeepManager;

    ERC20 public rewardToken;

    ERC20 public token0;
    ERC20 public token1;

    Users internal users;

    TestCLCallee public clCallee;
    NFTManagerCallee public nftCallee;

    CustomSwapFeeModule public customSwapFeeModule;
    CustomUnstakedFeeModule public customUnstakedFeeModule;
    DynamicSwapFeeModule public dynamicSwapFeeModule;

    string public nftName = "Slipstream Position NFT v1";
    string public nftSymbol = "CL-POS";

    function setUp() public virtual {
        users = Users({
            owner: createUser("Owner"),
            feeManager: createUser("FeeManager"),
            alice: createUser("Alice"),
            bob: createUser("Bob"),
            charlie: createUser("Charlie")
        });

        vm.startPrank(users.owner);
        rewardToken = new ERC20("", "");

        deployDependencies();
        deployContracts();
        postDeployment();

        deal({token: address(token0), to: users.alice, give: TOKEN_1 * 1000});
        deal({token: address(token1), to: users.alice, give: TOKEN_1 * 1000});
        deal({token: address(token0), to: users.charlie, give: TOKEN_1 * 1000});
        deal({token: address(token1), to: users.charlie, give: TOKEN_1 * 1000});

        vm.startPrank(users.alice);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);
        token0.approve(address(clCallee), type(uint256).max);
        token1.approve(address(clCallee), type(uint256).max);
        token0.approve(address(nftCallee), type(uint256).max);
        token1.approve(address(nftCallee), type(uint256).max);
        vm.startPrank(users.charlie);
        token0.approve(address(nft), type(uint256).max);
        token1.approve(address(nft), type(uint256).max);
        vm.stopPrank();

        labelContracts();
    }

    function postDeployment() public virtual {
        // backward compatibility with the original uniV3 fee structure and tick spacing
        poolFactory.enableTickSpacing(10, 500);
        poolFactory.enableTickSpacing(60, 3_000);
        // 200 tick spacing fee is manually overriden in tests as it is part of default settings

        // set nftmanager in the factories
        gaugeFactory.setNonfungiblePositionManager(address(nft));
        gaugeFactory.setNotifyAdmin(users.owner);
        vm.stopPrank();

        // approve gauge in factory registry
        vm.prank(Ownable(address(factoryRegistry)).owner());
        factoryRegistry.approve({
            poolFactory: address(poolFactory),
            votingRewardsFactory: address(votingRewardsFactory),
            gaugeFactory: address(gaugeFactory)
        });

        // transfer residual permissions
        vm.startPrank(users.owner);
        poolFactory.setOwner(users.owner);
        poolFactory.setSwapFeeManager(users.feeManager);
        poolFactory.setUnstakedFeeManager(users.feeManager);
        vm.stopPrank();

        vm.startPrank(users.feeManager);
        poolFactory.setSwapFeeModule(address(customSwapFeeModule));
        poolFactory.setUnstakedFeeModule(address(customUnstakedFeeModule));
        vm.stopPrank();

        // mock max emission cap in gauge factory
        vm.mockCall(
            address(gaugeFactory),
            abi.encodeWithSelector(CLGaugeFactory.calculateMaxEmissions.selector),
            abi.encode(type(uint256).max)
        );

        vm.prank(users.owner);
        gaugeFactory.setRedistributor(address(redistributor));
    }

    function deployContracts() public virtual {
        // deploy pool and associated contracts
        poolImplementation = new CLPool();
        poolFactory = new CLFactory({
            _voter: address(voter),
            _clFactory: address(legacyPoolFactory),
            _poolImplementation: address(poolImplementation)
        });

        // deploy gauges and associated contracts
        gaugeImplementation = new CLGauge();
        gaugeFactory = new CLGaugeFactory({
            _voter: address(voter),
            _implementation: address(gaugeImplementation),
            _emissionAdmin: users.owner,
            _defaultCap: 100,
            _legacyCLGaugeFactory: address(legacyGaugeFactory)
        });
        redistributor = new Redistributor({
            _voter: address(voter),
            _gaugeFactory: address(gaugeFactory),
            _upkeepManager: address(upkeepManager),
            _initialOwner: users.owner
        });

        // deploy nft manager and descriptor
        nftDescriptor = new NonfungibleTokenPositionDescriptor({
            _WETH9: address(weth),
            _nativeCurrencyLabelBytes: 0x4554480000000000000000000000000000000000000000000000000000000000 // 'ETH' as bytes32 string
        });
        nft = new NonfungiblePositionManager({
            _factory: address(poolFactory),
            _WETH9: address(weth),
            _tokenDescriptor: address(nftDescriptor),
            name: nftName,
            symbol: nftSymbol
        });

        customSwapFeeModule = new CustomSwapFeeModule(address(poolFactory));
        customUnstakedFeeModule = new CustomUnstakedFeeModule(address(poolFactory));
        ERC20 tokenA = new ERC20("", "");
        ERC20 tokenB = new ERC20("", "");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        clCallee = new TestCLCallee();
        nftCallee = new NFTManagerCallee(address(token0), address(token1), address(nft));
    }

    /// @dev Deploys mocks of external dependencies
    ///      Override if using a fork test
    function deployDependencies() public virtual {
        factoryRegistry = IFactoryRegistry(new MockFactoryRegistry());
        votingRewardsFactory = IVotingRewardsFactory(new MockVotingRewardsFactory());
        weth = IERC20(address(new MockWETH()));
        escrow = IVotingEscrow(new MockVotingEscrow(users.owner));
        minter = IMinter(new MockMinter({_aero: address(rewardToken)}));
        voter = IVoter(
            new MockVoter({
                _rewardToken: address(rewardToken),
                _factoryRegistry: address(factoryRegistry),
                _ve: address(escrow),
                _minter: address(minter)
            })
        );

        address mockFactory = address(new MockCLFactory());
        legacyPoolFactory =
            new CLFactory({_voter: address(voter), _clFactory: mockFactory, _poolImplementation: address(new CLPool())});

        legacyGaugeFactory = CLGaugeFactory(address(new MockCLGaugeFactory()));
        upkeepManager = new MockUpkeepManager();
    }

    /// @dev Helper utility to forward time to next week
    ///      note epoch requires at least one second to have
    ///      passed into the new epoch
    function skipToNextEpoch(uint256 offset) public {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }

    /// @dev Helper function to add rewards to gauge from voter
    function addRewardToGauge(address _voter, address _gauge, uint256 _amount) internal {
        deal(address(rewardToken), _voter, _amount);
        vm.startPrank(_voter);
        // do not overwrite approvals if already set
        if (rewardToken.allowance(_voter, _gauge) < _amount) {
            rewardToken.approve(_gauge, _amount);
        }
        CLGauge(payable(_gauge)).notifyRewardAmount(_amount);
        vm.stopPrank();
    }

    function labelContracts() internal virtual {
        vm.label({account: address(weth), newLabel: "WETH"});
        vm.label({account: address(voter), newLabel: "Voter"});
        vm.label({account: address(nftDescriptor), newLabel: "NFT Descriptor"});
        vm.label({account: address(nft), newLabel: "NFT Manager"});
        vm.label({account: address(poolImplementation), newLabel: "Pool Implementation"});
        vm.label({account: address(poolFactory), newLabel: "Pool Factory"});
        vm.label({account: address(token0), newLabel: "Token 0"});
        vm.label({account: address(token1), newLabel: "Token 1"});
        vm.label({account: address(rewardToken), newLabel: "Reward Token"});
        vm.label({account: address(gaugeFactory), newLabel: "Gauge Factory"});
        vm.label({account: address(customSwapFeeModule), newLabel: "Custom Swap FeeModule"});
        vm.label({account: address(customUnstakedFeeModule), newLabel: "Custom Unstaked Fee Module"});
        vm.label({account: address(legacyPoolFactory), newLabel: "Legacy Pool Factory"});
        vm.label({account: address(legacyGaugeFactory), newLabel: "Legacy Gauge Factory"});
    }

    function createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr({name: name}));
        vm.deal({account: user, newBalance: TOKEN_1 * 1_000});
    }
}
