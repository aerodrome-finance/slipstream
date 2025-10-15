// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract DepositIntegrationConcreteTest is RedistributorForkTest {
    using stdStorage for StdStorage;

    uint256 public constant amount = TOKEN_1 * 1_000;

    function setUp() public virtual override {
        super.setUp();

        skipToNextEpoch(30 minutes);
    }

    function test_WhenTheCallerIsNotAValidGauge() external {
        // It should revert with {NotGauge}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NG"));
        redistributor.deposit({_amount: amount});
    }

    modifier whenTheCallerIsAValidGauge() {
        deal(address(rewardToken), address(gauge), amount);

        vm.startPrank(address(gauge));
        rewardToken.approve(address(redistributor), amount);
        _;
    }

    modifier whenDepositIsCalledForTheFirstTimeInTheEpoch() {
        _;
    }

    function test_WhenDepositIsCalledBeforeRedistributes()
        external
        whenTheCallerIsAValidGauge
        whenDepositIsCalledForTheFirstTimeInTheEpoch
    {
        // It should store the total weight for the epoch
        // It should reduce the total weight by the gauge's weight
        // It should flag the gauge as excluded for the epoch
        // It should pull the emissions from the gauge
        // It should emit a {Deposited} event
        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        uint256 gaugeWeight = voter.weights({_pool: address(pool)});

        vm.expectEmit(address(redistributor));
        emit Deposited({gauge: address(gauge), to: address(redistributor), amount: amount});
        redistributor.deposit({_amount: amount});

        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight() - gaugeWeight);
        assertTrue(redistributor.isExcluded(epochStart, address(gauge)));
        assertEq(rewardToken.balanceOf(address(redistributor)), amount);
        assertEq(rewardToken.balanceOf(address(gauge)), 0);
    }

    function test_WhenDepositIsCalledDuringOrAfterRedistributes()
        external
        whenTheCallerIsAValidGauge
        whenDepositIsCalledForTheFirstTimeInTheEpoch
    {
        // It should store the total weight for the epoch
        // It should flag the gauge as excluded for the epoch
        // It should transfer the emissions from the gauge to the minter
        // It should emit a {Deposited} event
        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));

        /// @dev Set `totalEmissions` to simulate that redistribution has started
        deal(address(rewardToken), address(redistributor), amount);
        stdstore.target({_target: address(redistributor)}).sig({_sig: IRedistributor.totalEmissions.selector}).with_key({
            amt: uint256(epochStart)
        }).checked_write({amt: uint256(amount)});
        assertEq(redistributor.totalEmissions(epochStart), amount);

        vm.expectEmit(address(redistributor));
        emit Deposited({gauge: address(gauge), to: address(minter), amount: amount});
        redistributor.deposit({_amount: amount});

        assertEq(redistributor.totalWeight(epochStart), voter.totalWeight());
        assertTrue(redistributor.isExcluded(epochStart, address(gauge)));
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + amount);
        assertEq(rewardToken.balanceOf(address(redistributor)), amount);
        assertEq(rewardToken.balanceOf(address(gauge)), 0);
    }

    modifier whenDepositIsNotCalledForTheFirstTimeInTheEpoch() {
        deal(address(rewardToken), address(gauge2), amount);

        vm.startPrank(address(gauge2));
        rewardToken.approve(address(redistributor), amount);
        redistributor.deposit({_amount: amount});
        vm.stopPrank();

        vm.startPrank(address(gauge));
        _;
    }

    function test_WhenDepositIsCalledBeforeRedistributes_()
        external
        whenTheCallerIsAValidGauge
        whenDepositIsNotCalledForTheFirstTimeInTheEpoch
    {
        // It should reduce the total weight by the gauge's weight
        // It should flag the gauge as excluded for the epoch
        // It should pull the emissions from the gauge
        // It should emit a {Deposited} event
        uint256 totalWeight = voter.totalWeight();
        uint256 gaugeWeight = voter.weights({_pool: address(pool)});
        uint256 gaugeWeight2 = voter.weights({_pool: address(pool2)});
        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);

        assertEq(redistributor.totalWeight(epochStart), totalWeight - gaugeWeight2);

        vm.expectEmit(address(redistributor));
        emit Deposited({gauge: address(gauge), to: address(redistributor), amount: amount});
        redistributor.deposit({_amount: amount});

        assertEq(redistributor.totalWeight(epochStart), totalWeight - (gaugeWeight + gaugeWeight2));
        assertTrue(redistributor.isExcluded(epochStart, address(gauge)));
        assertEq(rewardToken.balanceOf(address(redistributor)), amount * 2);
        assertEq(rewardToken.balanceOf(address(gauge)), 0);
    }

    function test_WhenDepositIsCalledDuringOrAfterRedistributes_()
        external
        whenTheCallerIsAValidGauge
        whenDepositIsNotCalledForTheFirstTimeInTheEpoch
    {
        // It should flag the gauge as excluded for the epoch
        // It should transfer the emissions from the gauge to the minter
        // It should emit a {Deposited} event
        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 gaugeWeight2 = voter.weights({_pool: address(pool2)});
        uint256 totalWeight = voter.totalWeight();

        assertEq(redistributor.totalWeight(epochStart), totalWeight - gaugeWeight2);

        /// @dev Set `totalEmissions` to simulate that redistribution has started
        deal(address(rewardToken), address(redistributor), amount);
        stdstore.target({_target: address(redistributor)}).sig({_sig: IRedistributor.totalEmissions.selector}).with_key({
            amt: uint256(epochStart)
        }).checked_write({amt: uint256(amount)});
        assertEq(redistributor.totalEmissions(epochStart), amount);

        vm.expectEmit(address(redistributor));
        emit Deposited({gauge: address(gauge), to: address(minter), amount: amount});
        redistributor.deposit({_amount: amount});

        assertEq(redistributor.totalWeight(epochStart), totalWeight - gaugeWeight2);
        assertTrue(redistributor.isExcluded(epochStart, address(gauge)));
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + amount);
        assertEq(rewardToken.balanceOf(address(redistributor)), amount);
        assertEq(rewardToken.balanceOf(address(gauge)), 0);
    }

    function testGas_deposit() external whenTheCallerIsAValidGauge whenDepositIsCalledForTheFirstTimeInTheEpoch {
        redistributor.deposit({_amount: amount});
        vm.snapshotGasLastCall("Redistributor_deposit");
    }
}
