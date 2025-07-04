// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig_2of2.sol";

contract RedeemChannelTest is Test {
    Multisig multisig;
    address payer = address(0x1);
    address payee = address(0x2);
    address token = address(0); // native ETH
    uint256 amount = 1000;
    uint64 duration = 100;
    uint64 reclaimDelay = 200;

    function setUp() public {
        multisig = new Multisig();
        vm.deal(payer, 10 * amount);

        // Payer creates channel
        vm.startPrank(payer);
        multisig.createChannel{value: amount}(payee, address(0), amount, duration, reclaimDelay);
        vm.stopPrank();
    }
}
