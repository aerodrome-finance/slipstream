pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import {DeployDynamicFeeModule} from "script/DeployDynamicFeeModule.s.sol";

import {DynamicSwapFeeModule} from "contracts/core/fees/DynamicSwapFeeModule.sol";
import {CustomSwapFeeModule} from "contracts/core/fees/CustomSwapFeeModule.sol";
import {CLFactory} from "contracts/core/CLFactory.sol";
import {CLPool} from "contracts/core/CLPool.sol";

contract DeployDynamicFeeModuleForkTest is Test {
    using stdJson for string;

    DeployDynamicFeeModule public deployDynamicFee;

    DynamicSwapFeeModule public dynamicFeeModule;

    // deployed contracts
    CLFactory public clFactory;
    CustomSwapFeeModule public feeModule;

    address[] public pools;
    uint24[] public fees;

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "base", blockNumber: 26280000});
        clFactory = CLFactory(0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A);
        feeModule = CustomSwapFeeModule(clFactory.swapFeeModule());

        deployDynamicFee = new DeployDynamicFeeModule();

        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/logs/dynamicFees.json"));

        // load in vars
        string memory jsonConstants = vm.readFile(path);
        pools = abi.decode(jsonConstants.parseRaw(".pools"), (address[]));
        fees = abi.decode(jsonConstants.parseRaw(".customFees"), (uint24[]));
    }

    function test_deployDynamicFee() public {
        deployDynamicFee.run();
        dynamicFeeModule = deployDynamicFee.dynamicFeeModule();

        assertTrue(address(dynamicFeeModule) != address(0));

        assertEq(address(dynamicFeeModule.factory()), address(clFactory));
        assertEq(dynamicFeeModule.defaultScalingFactor(), 0);
        assertEq(dynamicFeeModule.defaultFeeCap(), 10_000); // 1%

        uint256 length = pools.length;
        assertEq(length, fees.length);

        address pool;
        uint24 customFee;
        uint24 existingCustomFee;
        // iterate through a subset of all pools to limit test workload
        for (uint256 i = 0; i < length; i++) {
            pool = pools[i];
            /// @dev Ensure custom fee is consistent with JSON input
            customFee = dynamicFeeModule.customFee(pool);
            assertEqUint(customFee, fees[i]);

            /// @dev Ensure new DynamicFeeModule migrates existing custom fees from the legacy module
            existingCustomFee = feeModule.customFee(pool);
            assertEqUint(customFee, existingCustomFee);
        }
    }
}
