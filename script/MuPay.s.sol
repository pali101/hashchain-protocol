// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MuPay} from "../src/MuPay.sol";

contract DeploySimpleStorage is Script {
    function run() external returns (MuPay) {
        vm.startBroadcast();

        MuPay muPay = new MuPay();

        vm.stopBroadcast();
        return muPay;
    }
}
