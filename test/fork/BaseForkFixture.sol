pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/StdJson.sol";
import "../BaseFixture.sol";

abstract contract BaseForkFixture is BaseFixture {
    using stdJson for string;

    uint256 public blockNumber = 12670000;
    string public addresses;
    IERC20 public dai;

    function setUp() public virtual override {
        vm.createSelectFork({urlOrAlias: "base", blockNumber: blockNumber});

        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/test/fork/addresses.json"));
        addresses = vm.readFile(path);

        // set up contracts after fork
        BaseFixture.setUp();

        nftCallee = new NFTManagerCallee(address(weth), address(dai), address(nft));

        deal({token: address(dai), to: users.alice, give: TOKEN_1 * 100});
        deal({token: address(weth), to: users.alice, give: TOKEN_1 * 100});

        vm.startPrank(users.alice);
        dai.approve(address(nftCallee), type(uint256).max);
        weth.approve(address(nftCallee), type(uint256).max);
        vm.stopPrank();
    }

    function deployDependencies() public virtual override {
        factoryRegistry = IFactoryRegistry(vm.parseJsonAddress(addresses, ".FactoryRegistry"));
        weth = IERC20(vm.parseJsonAddress(addresses, ".WETH"));
        dai = IERC20(vm.parseJsonAddress(addresses, ".DAI"));
        voter = IVoter(vm.parseJsonAddress(addresses, ".Voter"));
        rewardToken = ERC20(vm.parseJsonAddress(addresses, ".Aero"));
        votingRewardsFactory = IVotingRewardsFactory(vm.parseJsonAddress(addresses, ".VotingRewardsFactory"));
        escrow = IVotingEscrow(vm.parseJsonAddress(addresses, ".VotingEscrow"));
        minter = IMinter(vm.parseJsonAddress(addresses, ".Minter"));
    }

    function postDeployment() public virtual override {
        // backward compatibility with the original uniV3 fee structure and tick spacing
        poolFactory.enableTickSpacing(10, 500);
        poolFactory.enableTickSpacing(60, 3_000);
        // 200 tick spacing fee is manually overriden in tests as it is part of default settings

        // set nftmanager in the factories
        gaugeFactory.setNonfungiblePositionManager(address(nft));
        gaugeFactory.setNotifyAdmin(users.owner);
        vm.stopPrank();

        // approve gauge factory in factory registry
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
    }
}
