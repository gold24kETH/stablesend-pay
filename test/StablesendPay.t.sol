// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StablesendPay} from "../src/StablesendPay.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDC uses 6 decimals
    }
}

contract StablesendPayTest is Test {
    StablesendPay internal pay;
    MockUSDC internal usdc;

    address internal alice = address(0xA11CE); // payer
    address internal bob = address(0xB0B); // recipient
    address internal carol = address(0xCA201); // recipient

    uint256 internal constant ONE = 1e6; // 1 USDC

    function setUp() public {
        usdc = new MockUSDC();
        pay = new StablesendPay(address(usdc), 100); // 1% fee, owner = this
        usdc.mint(alice, 1_000 * ONE);
        vm.prank(alice);
        usdc.approve(address(pay), type(uint256).max);
    }

    // --- payTo ---

    function test_PayTo_CreditsNetOfFee() public {
        vm.prank(alice);
        pay.payTo(bob, 100 * ONE, "invoice #1");
        assertEq(pay.balanceOf(bob), 99 * ONE);
        assertEq(pay.feesAccrued(), 1 * ONE);
    }

    function test_PayTo_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(StablesendPay.ZeroAmount.selector);
        pay.payTo(bob, 0, "");
    }

    // --- withdraw ---

    function test_Withdraw_MovesUsdcToRecipient() public {
        vm.prank(alice);
        pay.payTo(bob, 100 * ONE, "");
        vm.prank(bob);
        pay.withdraw();
        assertEq(usdc.balanceOf(bob), 99 * ONE);
        assertEq(pay.balanceOf(bob), 0);
    }

    function test_Withdraw_RevertsWhenEmpty() public {
        vm.prank(bob);
        vm.expectRevert(StablesendPay.NothingToWithdraw.selector);
        pay.withdraw();
    }

    // --- batchPay ---

    function test_BatchPay_CreditsEachRecipient() public {
        address[] memory r = new address[](2);
        r[0] = bob;
        r[1] = carol;
        uint256[] memory a = new uint256[](2);
        a[0] = 50 * ONE;
        a[1] = 150 * ONE;

        vm.prank(alice);
        pay.batchPay(r, a, "driver payout June 2026");

        assertEq(pay.balanceOf(bob), 495 * ONE / 10); // 49.5 USDC
        assertEq(pay.balanceOf(carol), 1485 * ONE / 10); // 148.5 USDC
        assertEq(pay.feesAccrued(), 2 * ONE); // 0.5 + 1.5
        assertEq(usdc.balanceOf(address(pay)), 200 * ONE);
    }

    function test_BatchPay_RevertsOnLengthMismatch() public {
        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](1);
        vm.prank(alice);
        vm.expectRevert(StablesendPay.LengthMismatch.selector);
        pay.batchPay(r, a, "");
    }

    // --- requests / invoices ---

    function test_RequestFlow_PaysRequester() public {
        vm.prank(bob);
        uint256 id = pay.createRequest(200 * ONE, "freight KR->VN LCL");

        vm.prank(alice);
        pay.payRequest(id);
        assertEq(pay.balanceOf(bob), 198 * ONE);
    }

    function test_RequestFlow_CannotDoublePay() public {
        vm.prank(bob);
        uint256 id = pay.createRequest(200 * ONE, "");

        vm.prank(alice);
        pay.payRequest(id);

        vm.prank(alice);
        vm.expectRevert(StablesendPay.AlreadyPaid.selector);
        pay.payRequest(id);
    }

    function test_PayRequest_RevertsIfNotFound() public {
        vm.prank(alice);
        vm.expectRevert(StablesendPay.RequestNotFound.selector);
        pay.payRequest(999);
    }

    // --- fee cap ---

    function test_SetFee_RevertsAboveCap() public {
        vm.expectRevert(StablesendPay.FeeTooHigh.selector);
        pay.setFee(501); // > 5%
    }

    function test_SetFee_Works() public {
        pay.setFee(250);
        assertEq(pay.feeBps(), 250);
    }

    function test_WithdrawFees_OnlyOwner() public {
        vm.prank(alice);
        pay.payTo(bob, 100 * ONE, "");
        pay.withdrawFees(address(this));
        assertEq(usdc.balanceOf(address(this)), 1 * ONE);
        assertEq(pay.feesAccrued(), 0);
    }

    // --- handle registry ---

    function test_Handle_SetAndResolve() public {
        vm.prank(bob);
        pay.setHandle("tramcrypto68");
        assertEq(pay.resolveHandle("tramcrypto68"), bob);
    }

    function test_Handle_CannotStealTaken() public {
        vm.prank(bob);
        pay.setHandle("tramcrypto68");
        vm.prank(alice);
        vm.expectRevert(StablesendPay.HandleTaken.selector);
        pay.setHandle("tramcrypto68");
    }
}
