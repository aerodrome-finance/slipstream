// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract RedistributeIntegrationConcreteTest is RedistributorForkTest {
    using stdStorage for StdStorage;

    uint256 public epochStart;
    uint256 public totalEmissions;
    address public v2Gauge;
    address public legacyCLGauge;

    uint256 public epochStartSnapshot;
    uint256 public beforeVoteSnapshot;

    function setUp() public virtual override {
        super.setUp();

        /// @dev Set alice as an authorized keeper
        MockUpkeepManager(address(upkeepManager)).setUpkeep({_upkeep: users.alice, _state: true});
        v2Gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // USDC/AERO gauge
        legacyCLGauge = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8; // WETH/USDC legacy gauge

        skipToNextEpoch(0);
        epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
    }

    function _seedRedistributorAndCastVote() internal {
        /// @dev Reset redistributor balance
        deal(address(rewardToken), address(redistributor), 0);

        /// @dev Skip after distribute window and cast vote
        skipToNextEpoch(1 hours + 1);

        // Alice creates veNFT to vote
        deal(address(rewardToken), users.alice, TOKEN_1 * 1_000);
        vm.startPrank(users.alice);
        rewardToken.approve(address(escrow), TOKEN_1 * 1_000);
        uint256 tokenIdAlice = escrow.createLock(TOKEN_1 * 1_000, 365 days * 4);

        // Alice votes
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        voter.vote(tokenIdAlice, pools, votes);
        vm.stopPrank();

        /// @dev Skip to next epoch and deposit rewards into redistributor
        skipToNextEpoch(0);
        epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        epochStartSnapshot = vm.snapshot();

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(gauge2), totalEmissions);
        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);
    }

    function test_WhenTheCallerIsNotAGaugeUpkeepOrTheOwner() external {
        // It should revert with {NotAuthorized}
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        redistributor.redistribute({_gauges: gauges});
    }

    modifier whenTheCallerIsAGaugeUpkeepOrTheOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenCalledDuringTheFirst10MinutesOfTheEpoch() external whenTheCallerIsAGaugeUpkeepOrTheOwner {
        // It should revert with {TooSoon}
        assertLt(block.timestamp, epochStart + 10 minutes);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        vm.expectRevert(bytes("TS"));
        redistributor.redistribute({_gauges: gauges});
    }

    modifier whenCalledAfterTheFirst10MinutesOfTheEpoch() {
        skip(10 minutes);
        _;
    }

    function test_WhenThereAreNoEmissionsToRedistribute()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
    {
        // It should update the active period
        // It should skip the redistribution
        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        assertEq(redistributor.activePeriod(), epochStart);
        // @dev Total emissions remains unchanged
        assertEq(redistributor.totalEmissions(epochStart), 0);
    }

    modifier whenThereAreEmissionsToRedistribute() {
        totalEmissions = TOKEN_1 * 1_000;
        deal(address(rewardToken), address(redistributor), totalEmissions);
        _;
    }

    function test_WhenTheGaugeIsExcludedForTheEpoch()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should skip the gauge
        deal(address(rewardToken), address(gauge), TOKEN_1);

        vm.startPrank(address(gauge));
        rewardToken.approve(address(redistributor), TOKEN_1);
        redistributor.deposit({_amount: TOKEN_1});
        totalEmissions += TOKEN_1;
        vm.stopPrank();

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.startPrank(users.alice);
        redistributor.redistribute({_gauges: gauges});

        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
    }

    modifier whenTheGaugeIsNotExcludedForTheEpoch() {
        _;
    }

    function test_WhenTheGaugeHasAlreadyBeenRedistributedTo()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
    {
        // It should skip the gauge
        _seedRedistributorAndCastVote();

        vm.startPrank(users.alice);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        redistributor.redistribute({_gauges: gauges});

        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});
    }

    modifier whenTheGaugeHasNotBeenRedistributedTo() {
        _;
    }

    function test_WhenThereAreNoEmissionsToRedistributeToTheGauge()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        assertEq(voter.weights({_pool: address(pool)}), 0);

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    modifier whenThereAreEmissionsToRedistributeToTheGauge() {
        _seedRedistributorAndCastVote();
        _;
    }

    function test_WhenTheGaugeIsKilled()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should forward the emissions to the minter
        vm.startPrank(voter.emergencyCouncil());
        voter.killGauge(address(gauge));
        vm.stopPrank();

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: address(pool)}) / redistributor.totalWeight(epochStart);

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called
        vm.startPrank(users.alice);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        /// @dev Emissions are forwarded to minter
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    modifier whenTheGaugeIsAlive() {
        _;
    }

    function test_WhenTheGaugeHasNoEmissionCap()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event
        address[] memory gauges = new address[](1);
        gauges[0] = legacyCLGauge;

        uint256 oldGaugeBal = rewardToken.balanceOf(legacyCLGauge);
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        address legacyCLPool = voter.poolForGauge({_gauge: legacyCLGauge});
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: legacyCLPool}) / redistributor.totalWeight(epochStart);

        vm.startPrank(users.alice);
        vm.expectCall(
            legacyCLGauge, abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: legacyCLGauge, amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(legacyCLGauge), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, legacyCLGauge));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    function test_WhenTheGaugeHasNoEmissionCap_V2Gauge()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event
        address[] memory gauges = new address[](1);
        gauges[0] = v2Gauge;

        uint256 oldGaugeBal = rewardToken.balanceOf(v2Gauge);
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        address legacyCLPool = voter.poolForGauge({_gauge: v2Gauge});
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: legacyCLPool}) / redistributor.totalWeight(epochStart);

        vm.startPrank(users.alice);
        vm.expectCall(v2Gauge, abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions)));
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: v2Gauge, amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(v2Gauge), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, v2Gauge));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    modifier whenTheGaugeHasAnEmissionCap() {
        _;
    }

    function test_WhenTheGaugeReceivedNoDistributeThisEpoch()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should forward the emissions to the minter
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        assertEq(gauge.rewardsByEpoch(epochStart), 0);

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        address legacyCLPool = voter.poolForGauge({_gauge: address(gauge)});
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: legacyCLPool}) / redistributor.totalWeight(epochStart);

        vm.startPrank(users.alice);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        /// @dev Emissions are forwarded to minter
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    function test_WhenTheGaugeReceivedADistributeWithExcessEmissionsThisEpoch()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should forward the emissions to the minter
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        // @dev Exceed gauge's max cap via `notifyRewardWithoutClaim`
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});
        uint256 maxCapDelta = maxEmissions - gauge.rewardsByEpoch(epochStart);
        uint256 excess = TOKEN_1 * 100;
        deal(address(rewardToken), users.owner, maxCapDelta + excess);
        vm.startPrank(users.owner);
        rewardToken.approve(address(redistributor), maxCapDelta + excess);
        redistributor.notifyRewardWithoutClaim({_gauge: address(gauge), _amount: maxCapDelta + excess});

        assertEq(gauge.rewardsByEpoch(epochStart), maxEmissions + excess);

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(gauge2), totalEmissions);
        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        address legacyCLPool = voter.poolForGauge({_gauge: address(gauge)});
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: legacyCLPool}) / redistributor.totalWeight(epochStart);

        vm.startPrank(users.alice);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        /// @dev Emissions are forwarded to minter
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    modifier whenTheGaugeReceivedADistributeThisEpoch() {
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(gauge2), totalEmissions);
        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);
        _;
    }

    function test_WhenTheRecycledEmissionsExceedTheMaxCap()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should forward the excess emissions to the minter
        // It should notify the gauge without claiming fees up to its max cap
        // It should emit a {Redistributed} event

        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 5_000_000;
        deal(address(rewardToken), address(gauge2), totalEmissions);
        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);

        uint256 prevEmissions = gauge.rewardsByEpoch(epochStart);
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        // @dev Calculate total weight ratio required to exceed max emissions
        uint256 requiredEmissions = maxEmissions - prevEmissions;
        uint256 ratio = totalEmissions / requiredEmissions;
        uint256 maxWeight = voter.totalWeight() / ratio;

        assertGt(prevEmissions, 0);

        /// @dev Overwrite gauge weight to simulate emission overflow
        stdstore.target({_target: address(voter)}).sig({_sig: IVoter.weights.selector}).with_key({who: address(pool)})
            .checked_write({amt: uint256(maxWeight)});

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: address(pool)}) / redistributor.totalWeight(epochStart);

        vm.startPrank(users.alice);
        vm.expectCall(
            address(gauge),
            abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (maxEmissions - prevEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: maxEmissions - prevEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives emissions up to the max cap
        assertEq(rewardToken.balanceOf(address(gauge)), maxEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);
        // @dev Minter receives excess emissions
        uint256 excessEmissions = gaugeEmissions + prevEmissions - maxEmissions;
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + excessEmissions);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    modifier whenTheRecycledEmissionsDoNotExceedTheMaxCap() {
        _;
    }

    modifier whenRedistributeIsCalledForTheFirstTimeInTheEpoch() {
        _;
    }

    function test_WhenDepositHasBeenCalledInTheEpoch()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
        whenTheRecycledEmissionsDoNotExceedTheMaxCap
        whenRedistributeIsCalledForTheFirstTimeInTheEpoch
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event
        uint256 oldGaugeBal = rewardToken.balanceOf(address(gauge));
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: address(pool)}) / redistributor.totalWeight(epochStart);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        vm.startPrank(users.alice);
        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(address(gauge)), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);
        // @dev Minter balance remains unchanged
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    function test_WhenDepositHasNotBeenCalledInTheEpoch()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
        whenTheRecycledEmissionsDoNotExceedTheMaxCap
        whenRedistributeIsCalledForTheFirstTimeInTheEpoch
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should update the total weight for the epoch
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event

        // @dev Revert to snapshot to simulate an epoch with no deposit
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards directly into redistributor to simulate rolled over emissions
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(redistributor), totalEmissions);

        skip(10 minutes);

        uint256 oldGaugeBal = rewardToken.balanceOf(address(gauge));
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions = totalEmissions * voter.weights({_pool: address(pool)}) / voter.totalWeight();

        assertEq(redistributor.totalWeight(epochStart), 0);

        vm.startPrank(users.alice);
        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(address(gauge)), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);
        // @dev Minter balance remains unchanged
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
    }

    modifier whenRedistributeIsNotCalledForTheFirstTimeInTheEpoch() {
        _;
    }

    function test_WhenDepositHasBeenCalledInTheEpoch_()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
        whenTheRecycledEmissionsDoNotExceedTheMaxCap
        whenRedistributeIsNotCalledForTheFirstTimeInTheEpoch
    {
        // It should signal the gauge received its redistribute this epoch
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event
        vm.startPrank(users.alice);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge2);
        redistributor.redistribute({_gauges: gauges});
        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);

        uint256 oldGaugeBal = rewardToken.balanceOf(address(gauge));
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: address(pool)}) / redistributor.totalWeight(epochStart);

        gauges = new address[](1);
        gauges[0] = address(gauge);

        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(address(gauge)), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);
        // @dev Minter balance remains unchanged
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));

        // @dev Cached state remains unchanged
        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    function test_WhenDepositHasNotBeenCalledInTheEpoch_()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
        whenTheRecycledEmissionsDoNotExceedTheMaxCap
        whenRedistributeIsNotCalledForTheFirstTimeInTheEpoch
    {
        // It should signal the gauge received its redistribute this epoch
        // It should update the total weight for the epoch
        // It should notify the gauge without claiming fees
        // It should emit a {Redistributed} event

        // @dev Revert to snapshot to simulate an epoch with no deposit
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards directly into redistributor to simulate rolled over emissions
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(redistributor), totalEmissions);

        skip(10 minutes);

        vm.startPrank(users.alice);
        gauges = new address[](1);
        gauges[0] = address(gauge2);
        redistributor.redistribute({_gauges: gauges});
        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);

        uint256 oldGaugeBal = rewardToken.balanceOf(address(gauge));
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));
        uint256 gaugeEmissions =
            totalEmissions * voter.weights({_pool: address(pool)}) / redistributor.totalWeight(epochStart);

        gauges = new address[](1);
        gauges[0] = address(gauge);

        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ICLGauge.notifyRewardWithoutClaim.selector, (gaugeEmissions))
        );
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: gaugeEmissions});
        redistributor.redistribute({_gauges: gauges});

        /// @dev Gauge receives full emission amount
        assertEq(rewardToken.balanceOf(address(gauge)), oldGaugeBal + gaugeEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(rewardToken.balanceOf(address(redistributor)), oldRedistributorBal - gaugeEmissions);
        // @dev Minter balance remains unchanged
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal);

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));

        // @dev Cached state remains unchanged
        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
    }

    function testGas_redistribute()
        external
        whenTheCallerIsAGaugeUpkeepOrTheOwner
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
        whenTheGaugeIsNotExcludedForTheEpoch
        whenTheGaugeHasNotBeenRedistributedTo
        whenThereAreEmissionsToRedistributeToTheGauge
        whenTheGaugeIsAlive
        whenTheGaugeHasAnEmissionCap
        whenTheGaugeReceivedADistributeThisEpoch
    {
        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 5_000_000;
        deal(address(rewardToken), address(gauge2), totalEmissions);
        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);

        uint256 prevEmissions = gauge.rewardsByEpoch(epochStart);
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        // @dev Calculate total weight ratio required to exceed max emissions
        uint256 requiredEmissions = maxEmissions - prevEmissions;
        uint256 ratio = totalEmissions / requiredEmissions;
        uint256 maxWeight = voter.totalWeight() / ratio;

        /// @dev Overwrite gauge weight to simulate emission overflow
        stdstore.target({_target: address(voter)}).sig({_sig: IVoter.weights.selector}).with_key({who: address(pool)})
            .checked_write({amt: uint256(maxWeight)});

        vm.prank(users.owner);
        redistributor.redistribute({_gauges: gauges});
        vm.snapshotGasLastCall("Redistributor_redistribute");
    }
}
