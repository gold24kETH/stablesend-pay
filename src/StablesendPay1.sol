// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StablesendPay is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    uint16 public constant MAX_FEE_BPS = 500;
    uint16 public feeBps;
    uint256 private constant MAX_MEMO = 280;

    mapping(address => uint256) public balanceOf;
    uint256 public feesAccrued;

    mapping(bytes32 => address) public handleToAddress;
    mapping(address => string) public addressToHandle;

    struct Request { address requester; uint256 amount; bool paid; string memo; }
    uint256 public requestCount;
    mapping(uint256 => Request) public requests;

    error ZeroAmount();
    error FeeTooHigh();
    error LengthMismatch();
    error NothingToWithdraw();
    error HandleTaken();
    error EmptyHandle();
    error RequestNotFound();
    error AlreadyPaid();
    error MemoTooLong();

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

    function payTo(address to, uint256 amount, string calldata memo) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (bytes(memo).length > MAX_MEMO) revert MemoTooLong();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[to] += amount - fee;
        emit Payment(msg.sender, to, amount, fee, memo);
    }

    function tip(address to, uint256 amount, string calldata message) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (bytes(message).length > MAX_MEMO) revert MemoTooLong();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[to] += amount - fee;
        emit Tip(msg.sender, to, amount, fee, message);
    }

    function batchPay(address[] calldata recipients, uint256[] calldata amounts, string calldata memo)
        external nonReentrant
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

    function createRequest(uint256 amount, string calldata memo) external returns (uint256 id) {
        if (amount == 0) revert ZeroAmount();
        if (bytes(memo).length > MAX_MEMO) revert MemoTooLong();
        id = ++requestCount;
        requests[id] = Request({requester: msg.sender, amount: amount, paid: false, memo: memo});
        emit RequestCreated(id, msg.sender, amount, memo);
    }

    function payRequest(uint256 id) external nonReentrant {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestNotFound();
        if (r.paid) revert AlreadyPaid();
        r.paid = true;
        uint256 amount = r.amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = (amount * feeBps) / 10_000;
        feesAccrued += fee;
        balanceOf[r.requester] += amount - fee;
        emit RequestPaid(id, msg.sender, amount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        balanceOf[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

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
