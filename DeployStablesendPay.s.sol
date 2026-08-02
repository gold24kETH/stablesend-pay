// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {StablesendPay} from "../src/StablesendPay.sol";

/**
 * @notice Deploy StablesendPay to Arc Testnet.
 *
 *   Chain ID : 5042002
 *   RPC      : https://rpc.testnet.arc.network
 *   USDC     : 0x3600000000000000000000000000000000000000  (native)
 *
 * Usage:
 *   forge script script/DeployStablesendPay.s.sol \
 *     --rpc-url https://rpc.testnet.arc.network \
 *     --broadcast -vvvv
 *
 * Requires PRIVATE_KEY in your .env (never commit it).
 */
contract DeployStablesendPay is Script {
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;
    uint16 internal constant FEE_BPS = 100; // 1%

    function run() external returns (StablesendPay pay) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        pay = new StablesendPay(ARC_USDC, FEE_BPS);
        console2.log("StablesendPay deployed at:", address(pay));
        vm.stopBroadcast();
    }
}
