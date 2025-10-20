// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract SetUpkeepManagerIntegrationConcreteTest is RedistributorForkTest {
    address newUpkeepManager;

    function setUp() public override {
        super.setUp();
        newUpkeepManager = address(0x1234);
    }

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {"Ownable: caller is not the owner"}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        redistributor.setUpkeepManager({_upkeepManager: newUpkeepManager});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenTheUpkeepManagerIsZeroAddress() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroAddress}
        vm.expectRevert(bytes("ZA"));
        redistributor.setUpkeepManager({_upkeepManager: address(0)});
    }

    function test_WhenTheUpkeepManagerIsNotZeroAddress() external whenTheCallerIsTheOwner {
        // It should set the new upkeep manager
        // It should emit a {SetUpkeepManager} event
        vm.expectEmit(address(redistributor));
        emit SetUpkeepManager({upkeepManager: newUpkeepManager});
        redistributor.setUpkeepManager({_upkeepManager: newUpkeepManager});

        assertEq(redistributor.upkeepManager(), newUpkeepManager);
    }
}
