// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGaugeFactory.t.sol";

contract SetRedistributorIntegrationConcreteTest is CLGaugeFactoryForkTest {
    address newRedistributor;

    function test_WhenCallerIsNotTheEmissionAdmin() external {
        // It should revert with {NotAuthorized}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        gaugeFactory.setRedistributor({_redistributor: address(0)});
    }

    modifier whenCallerIsTheEmissionAdmin() {
        vm.startPrank(gaugeFactory.emissionAdmin());
        _;
    }

    function test_WhenRedistributorIsZeroAddress() external whenCallerIsTheEmissionAdmin {
        // It should revert with {ZeroAddress}
        vm.expectRevert(bytes("ZA"));
        gaugeFactory.setRedistributor({_redistributor: address(0)});
    }

    modifier whenRedistributorIsNotZeroAddress() {
        newRedistributor = address(new MockRedistributor({_rewardToken: address(rewardToken)}));

        _;
    }

    function test_WhenRedistributorIsVotingEscrowTeam()
        external
        whenRedistributorIsNotZeroAddress
        whenCallerIsTheEmissionAdmin
    {
        // It should revert with {EscrowTeam}
        vm.expectRevert(bytes("ET"));
        gaugeFactory.setRedistributor({_redistributor: newRedistributor});
    }

    modifier whenRedistributorIsNotVotingEscrowTeam() {
        vm.prank(escrow.team());
        escrow.setTeam({_team: address(newRedistributor)});
        _;
    }

    function test_WhenRedistributorIsTheLegacyGaugeFactoryNotifyAdmin()
        external
        whenRedistributorIsNotZeroAddress
        whenRedistributorIsNotVotingEscrowTeam
        whenCallerIsTheEmissionAdmin
    {
        // It should revert with {LegacyNotifyAdmin}
        vm.expectRevert(bytes("LNA"));
        gaugeFactory.setRedistributor({_redistributor: newRedistributor});
    }

    function test_WhenRedistributorIsNotTheLegacyGaugeFactoryNotifyAdmin()
        external
        whenRedistributorIsNotZeroAddress
        whenRedistributorIsNotVotingEscrowTeam
        whenCallerIsTheEmissionAdmin
    {
        // It should set the new redistributor
        // It should emit a {SetRedistributor} event
        vm.startPrank(gaugeFactory.notifyAdmin());
        legacyGaugeFactory.setNotifyAdmin({_admin: newRedistributor});
        vm.stopPrank();

        vm.startPrank(gaugeFactory.emissionAdmin());
        vm.expectEmit(address(gaugeFactory));
        emit SetRedistributor({_newRedistributor: newRedistributor});
        gaugeFactory.setRedistributor({_redistributor: newRedistributor});

        assertEq(gaugeFactory.redistributor(), newRedistributor);
    }
}
