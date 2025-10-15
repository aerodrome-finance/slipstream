// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

contract MockCLGaugeFactory {
    address public notifyAdmin;

    constructor() {
        notifyAdmin = address(1);
    }

    function setNotifyAdmin(address _admin) external {
        notifyAdmin = _admin;
    }
}
