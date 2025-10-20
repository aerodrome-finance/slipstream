// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract TransferPermissionsIntegrationConcreteTest is RedistributorForkTest {
    using stdStorage for StdStorage;

    address public newRedistributor;

    function setUp() public virtual override {
        super.setUp();

        // remove redistributor permissions for testing purposes
        vm.prank(address(redistributor));
        escrow.setTeam({_team: users.owner});

        vm.prank(address(redistributor));
        legacyGaugeFactory.setNotifyAdmin({_admin: users.owner});
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        // It should revert with {Ownable: caller is not the owner}
        vm.prank(users.charlie);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        redistributor.transferPermissions({_newRedistributor: newRedistributor});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenTheNewRedistributorIsTheZeroAddress() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroAddress}
        vm.expectRevert(abi.encodePacked("ZA"));
        redistributor.transferPermissions({_newRedistributor: address(0)});
    }

    modifier whenTheNewRedistributorIsNotTheZeroAddress() {
        newRedistributor = address(
            new Redistributor({
                _voter: address(voter),
                _gaugeFactory: address(gaugeFactory),
                _upkeepManager: address(upkeepManager),
                _initialOwner: users.owner
            })
        );
        _;
    }

    function test_WhenTheRedistributorIsNotEscrowTeam()
        external
        whenTheCallerIsTheOwner
        whenTheNewRedistributorIsNotTheZeroAddress
    {
        // It should revert with {NotTeam}
        // will revert inside voting escrow
        vm.expectRevert({reverter: address(escrow)});
        redistributor.transferPermissions({_newRedistributor: newRedistributor});
    }

    modifier whenTheRedistributorIsEscrowTeam() {
        escrow.setTeam({_team: address(redistributor)});
        _;
    }

    function test_WhenTheRedistributorIsNotTheLegacyGaugeFactoryNotifyAdmin()
        external
        whenTheCallerIsTheOwner
        whenTheNewRedistributorIsNotTheZeroAddress
        whenTheRedistributorIsEscrowTeam
    {
        // It should revert with {NotAuthorized}
        vm.expectRevert(bytes("NA"));
        redistributor.transferPermissions({_newRedistributor: newRedistributor});
    }

    function test_WhenTheRedistributorIsTheLegacyGaugeFactoryNotifyAdmin()
        external
        whenTheCallerIsTheOwner
        whenTheNewRedistributorIsNotTheZeroAddress
        whenTheRedistributorIsEscrowTeam
    {
        // It should set the new redistributor as the escrow team
        // It should set the new redistributor as the legacy gauge factory notify admin
        // It should emit a {PermissionsTransferred} event
        legacyGaugeFactory.setNotifyAdmin({_admin: address(redistributor)});

        vm.expectEmit(address(redistributor));
        emit PermissionsTransferred({redistributor: address(redistributor), newRedistributor: newRedistributor});
        redistributor.transferPermissions({_newRedistributor: newRedistributor});

        assertEq(escrow.team(), newRedistributor);
        assertEq(legacyGaugeFactory.notifyAdmin(), newRedistributor);
    }
}
