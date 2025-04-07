// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract VerifyHashchainTest is Test {
    MuPay public muPay;

    function setUp() public {
        muPay = new MuPay();
    }

    function testValidHashchain() public view {
        bytes32 finalHash = keccak256(abi.encode("seed"));
        uint16 depth = 100;
        bytes32 trustAnchor = finalHash;

        for (uint16 i = 0; i < depth; i++) {
            trustAnchor = keccak256(abi.encode(trustAnchor));
        }

        bool isValid = muPay.verifyHashchain(trustAnchor, finalHash, depth);
        assertEq(isValid, true, "Hashchain should be vaild");
    }

    function testInvalidHashchain() public view {
        bytes32 finalHash = keccak256(abi.encode("seed"));
        uint16 depth = 100;
        bytes32 trustAnchor = keccak256(abi.encode("wrong-seed"));

        bool isValid = muPay.verifyHashchain(trustAnchor, finalHash, depth);
        assertEq(false, isValid, "Hashchain with wrong trust anchor should be invalid");
    }

    function testInvalidHashchainWrongDepth() public {
        bytes32 finalHash = keccak256(abi.encode("seed"));
        uint16 depth = 100;
        bytes32 trustAnchor = finalHash;

        for (uint16 i = 0; i < depth; i++) {
            trustAnchor = keccak256(abi.encode(trustAnchor));
        }

        bool isValid = muPay.verifyHashchain(trustAnchor, finalHash, depth + 1);
        assertEq(false, isValid, "Hashchain with wrong depth should be invalid");
    }
}
