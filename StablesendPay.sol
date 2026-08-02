// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StablesendPay
 * @notice USDC payments rail on Arc Network — evolves Stablesend from creator
 *         tipping into a general programmable-money primitive: direct pay,
 *         batch disbursement (payroll / vendor payouts), and payment requests
 *         (invoices). Pull-payment accounting throughout; fee hard-capped at 5%.
 *
 *         Built on Arc (Chain ID 5042002). USDC is the native gas token, so
 *         both fees and settlement are denominated in dollars.
 */
contract StablesendPay is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // --- config ---
    IERC20 public immutable usdc;
    uint16 public constant MAX_FEE_BPS = 500; // 5% anti-rug hard cap
    uint16 public feeBps; // platform fee, default 100 = 1%
    uint256 private constant MAX_MEMO = 280; // tweet-sized memos

    // --- pull-payment ledger ---
    mapping(address => uint256) public balanceOf; // withdrawable USDC per recipient
    uint256 public feesAccrued; // owner-withdrawable protocol fees

    // --- handle registry (kept from Stablesend) ---
    mapping(bytes32 => address) public handleToAddress;
    mapping(address => string) public addressToHandle;

    // --- payment requests / invoices ---
    struct Request {
        address requester;
        uint256 amount;
        bool paid;
        string memo;
    }

    uint256 public requestCount;
    mapping(uint256 => Request) public requests;

    // --- errors (gas-cheap custom errors) ---
    error ZeroAmount();
    error FeeTooHigh();
    error LengthMismatch();
    error NothingToWithdraw();
    error HandleTaken();
    error EmptyHandle();
    error RequestNotFound();
    error AlreadyPaid();
    error MemoTooLong();

    // --- events (indexer-friendly for the leaderboard / dashboard) ---
    event Payment(address indexed from, address indexed to, uint256 amount, uint256 fee, string memo);
    event Tip(address indexed from, address indexed to, uint256 amount, uint256 fee, string message);
    event BatchPayment(address indexed from, uint256 totalAmount, uint256 recipients, string memo);
    event Withdrawn(address indexed who, uint256 amount);
    event HandleSet(address indexed who, string handle);
    event RequestCreated(uint256 indexed id, address indexed requester, uint256 amount, string memo);
    event RequestPaid(uint256 indexed id, address indexed payer, uint256 amount);
    event FeeUpdated(uint16 feeBps);

    constructor(address _usdc, uint16 _feeBps) Ownable(msg.sender) {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        usdc = IERC20(_usdc);
        feeBps = _feeBps;
    }

    // ----------------------------------------------------------------
    //  Core payments
    // ----------------------------------------------------------------

    /// @notice Generic direct payment. Payer must approve `amount` first.
    function payTo(address to, uint256 amount, string calldata memo) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (bytes(memo).length > MAX_MEMO) revert MemoTooLong();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[to] += amount - fee;
        emit Payment(msg.sender, to, amount, fee, memo);
    }

    /// @notice Backwards-compatible creator tip (same mechanics, different event).
    function tip(address to, uint256 amount, string calldata message) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (bytes(message).length > MAX_MEMO) revert MemoTooLong();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[to] += amount - fee;
        emit Tip(msg.sender, to, amount, fee, message);
    }

    /// @notice Pay many recipients in one transaction (payroll / vendor payouts).
    ///         One approval, one transfer-in, then per-recipient crediting.
    function batchPay(address[] calldata recipients, uint256[] calldata amounts, string calldata memo)
        external
        nonReentrant
    {
        uint256 n = recipients.length;
        if (n == 0) revert ZeroAmount();
        if (n != amounts.length) revert LengthMismatch();
        if (bytes(memo).length > MAX_MEMO) revert MemoTooLong();

        uint256 total;
        for (uint256 i; i < n; ++i) {
            if (amounts[i] == 0) revert ZeroAmount();
            total += amounts[i];
        }
        usdc.safeTransferFrom(msg.sender, address(this), total);

        uint256 feeTotal;
        for (uint256 i; i < n; ++i) {
            uint256 fee = (amounts[i] * feeBps) / 10_000;
            feeTotal += fee;
            balanceOf[recipients[i]] += amounts[i] - fee;
        }
        feesAccrued += feeTotal;
        emit BatchPayment(msg.sender, total, n, memo);
    }

    // ----------------------------------------------------------------
    //  Payment requests / invoices
    // ----------------------------------------------------------------

    /// @notice Create an on-chain invoice others can settle with `payRequest`.
    function createRequest(uint256 amount, string calldata memo) external returns (uint256 id) {
        if (amount == 0) revert ZeroAmount();
        if (bytes(memo).length > MAX_MEMO) revert MemoTooLong();
        id = ++requestCount;
        requests[id] = Request({requester: msg.sender, amount: amount, paid: false, memo: memo});
        emit RequestCreated(id, msg.sender, amount, memo);
    }

    /// @notice Settle an open invoice. Payer must approve `amount` first.
    function payRequest(uint256 id) external nonReentrant {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestNotFound();
        if (r.paid) revert AlreadyPaid();
        r.paid = true; // effects before interaction

        uint256 amount = r.amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[r.requester] += amount - fee;
        emit RequestPaid(id, msg.sender, amount);
    }

    // ----------------------------------------------------------------
    //  Withdrawals (pull-payment)
    // ----------------------------------------------------------------

    function withdraw() external nonReentrant {
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        balanceOf[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // ----------------------------------------------------------------
    //  Handle registry
    // ----------------------------------------------------------------

    function setHandle(string calldata handle) external {
        if (bytes(handle).length == 0) revert EmptyHandle();
        bytes32 key = keccak256(bytes(handle));
        address existing = handleToAddress[key];
        if (existing != address(0) && existing != msg.sender) revert HandleTaken();
        handleToAddress[key] = msg.sender;
        addressToHandle[msg.sender] = handle;
        emit HandleSet(msg.sender, handle);
    }

    function resolveHandle(string calldata handle) external view returns (address) {
        return handleToAddress[keccak256(bytes(handle))];
    }

    // ----------------------------------------------------------------
    //  Owner
    // ----------------------------------------------------------------

    function setFee(uint16 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 amount = feesAccrued;
        if (amount == 0) revert NothingToWithdraw();
        feesAccrued = 0;
        usdc.safeTransfer(to, amount);
    }
}
