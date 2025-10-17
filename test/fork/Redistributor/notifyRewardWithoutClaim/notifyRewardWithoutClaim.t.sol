// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract NotifyRewardWithoutClaimIntegrationConcreteTest is RedistributorForkTest {
    uint256 public amount;
    address public v2Gauge;
    address public clGauge;

    function setUp() public virtual override {
        super.setUp();
        v2Gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // USDC/AERO gauge
        clGauge = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8; // WETH/USDC legacy gauge

        // give notify admin permission in legacy gauge factory to redistributor
        legacyGaugeFactory = CLGaugeFactory(address(CLGauge(payable(clGauge)).gaugeFactory()));
        vm.prank(legacyGaugeFactory.notifyAdmin());
        legacyGaugeFactory.setNotifyAdmin({_admin: address(redistributor)});
    }

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {"Ownable: caller is not the owner"}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        redistributor.notifyRewardWithoutClaim({_gauge: address(gauge), _amount: amount});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenTheAmountIsZero() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroReward}
        vm.expectRevert(bytes("ZR"));
        redistributor.notifyRewardWithoutClaim({_gauge: address(gauge), _amount: amount});
    }

    modifier whenTheAmountIsNotZero() {
        amount = 1_000 * TOKEN_1;
        deal(address(rewardToken), users.owner, amount * 3);
        rewardToken.approve(address(redistributor), amount * 3);
        _;
    }

    function test_WhenTheGaugeIsNotAValidGauge() external whenTheCallerIsTheOwner whenTheAmountIsNotZero {
        // It should revert with {NotGauge}
        vm.expectRevert(bytes("NG"));
        redistributor.notifyRewardWithoutClaim({_gauge: address(0), _amount: amount});
    }

    function test_WhenTheGaugeIsAValidGauge() external whenTheCallerIsTheOwner whenTheAmountIsNotZero {
        // It should transfer the reward amount from the caller
        // It should notify reward without claim on the gauge with the amount
        // It should emit a {NotifyRewardWithoutClaim} event
        uint256 balanceV2Gauge = rewardToken.balanceOf(v2Gauge);
        uint256 balanceCLGauge = rewardToken.balanceOf(clGauge);

        // test with clgauge
        vm.expectEmit(address(redistributor));
        emit NotifyRewardWithoutClaim({gauge: address(gauge), amount: amount});
        redistributor.notifyRewardWithoutClaim({_gauge: address(gauge), _amount: amount});

        assertEq(rewardToken.balanceOf(users.owner), amount * 2);
        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), amount);

        //test with legacy cl gauge
        vm.expectEmit(address(redistributor));
        emit NotifyRewardWithoutClaim({gauge: clGauge, amount: amount});
        redistributor.notifyRewardWithoutClaim({_gauge: clGauge, _amount: amount});

        assertEq(rewardToken.balanceOf(users.owner), amount);
        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        assertEq(rewardToken.balanceOf(clGauge), balanceCLGauge + amount);

        // test with v2 gauge
        vm.expectEmit(address(redistributor));
        emit NotifyRewardWithoutClaim({gauge: v2Gauge, amount: amount});
        redistributor.notifyRewardWithoutClaim({_gauge: v2Gauge, _amount: amount});

        assertEq(rewardToken.balanceOf(users.owner), 0);
        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        assertEq(rewardToken.balanceOf(v2Gauge), balanceV2Gauge + amount);
    }
}
