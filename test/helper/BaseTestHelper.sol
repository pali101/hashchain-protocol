// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

contract BaseTestHelper is Test {
    uint256 PAYER1PK = 1;
    uint256 PAYER2PK = 2;
    uint256 PAYEE1PK = 3;
    uint256 PAYEE2PK = 4;
    uint256 OWNERPK = 5;

    address public immutable PAYER = vm.addr(PAYER1PK);
    address public immutable PAYER2 = vm.addr(PAYER2PK);
    address public immutable PAYEE = vm.addr(PAYEE1PK);
    address public immutable PAYEE2 = vm.addr(PAYEE2PK);
    address public immutable OWNER = vm.addr(OWNERPK);

    address public NATIVE_TOKEN = address(0);
    uint64 public constant DURATION = 100;
    uint64 public constant RECLAIM_DELAY = 1000;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant DEPOSIT_AMOUNT = 10 ether;
}
