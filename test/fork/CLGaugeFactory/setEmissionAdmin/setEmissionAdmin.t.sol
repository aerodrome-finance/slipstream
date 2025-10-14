// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGaugeFactory.t.sol";

contract SetEmissionAdminIntegrationConcreteTest is CLGaugeFactoryForkTest {
    function test_WhenCallerIsNotTheEmissionAdmin() external {
        // It should revert with {NotAuthorized}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        gaugeFactory.setEmissionAdmin({_admin: users.charlie});
    }

    modifier whenCallerIsTheEmissionAdmin() {
        vm.prank(gaugeFactory.emissionAdmin());
        _;
    }

    function test_WhenAdminIsTheZeroAddress() external whenCallerIsTheEmissionAdmin {
        // It should revert with {ZeroAddress}
        vm.expectRevert(bytes("ZA"));
        gaugeFactory.setEmissionAdmin({_admin: address(0)});
    }

    function test_WhenAdminIsNotTheZeroAddress() external whenCallerIsTheEmissionAdmin {
        // It should set the new emission admin
        // It should emit a {EmissionAdminSet} event
        vm.expectEmit(address(gaugeFactory));
        emit SetEmissionAdmin({_emissionAdmin: users.alice});
        gaugeFactory.setEmissionAdmin({_admin: users.alice});

        assertEq(gaugeFactory.emissionAdmin(), users.alice);
    }
}
