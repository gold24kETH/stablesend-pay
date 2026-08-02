# StablesendPay — Programmable Money Hackathon (Build on Arc)

**Track:** Payments & Treasury / Fintech infrastructure
**Base:** nâng cấp từ Stablesend (creator tipping) → payments rail đa dụng trên Arc.

---

## Pitch (1 dòng)

> Stablesend bắt đầu là công cụ tip USDC cho creator. StablesendPay biến nó
> thành đường ray thanh toán USDC cho Đông Nam Á: **trả trực tiếp, chi hàng
> loạt (payroll/vendor), và hóa đơn on-chain** — settle dưới 1 giây, phí tính
> bằng đô, không phụ thuộc ngân hàng.

## Vì sao đáng chú ý (unfair advantage)

Mình làm điều phối vận tải LCL cho khách Hàn: dòng tiền chạy KRW/USD → VND →
tài xế/vendor/cảng. Chuyển khoản ngân hàng chậm 2–7 ngày, dính spread FX, đối
soát hóa đơn thủ công. Đây là bài toán thật mình gặp mỗi ngày — và
`batchPay` giải đúng nó: **một giao dịch chi cước cho nhiều tài xế/vendor cùng
lúc bằng USDC**, thay vì hàng chục lệnh chuyển khoản.

Cùng lúc vẫn giữ được câu chuyện creator (mình là Arc Architect Tier 1, làm nội
dung cho cộng đồng VN/SEA) — nên demo có cả hai mặt: creator payout và freight
payout.

## Ba tính năng thêm vào (so với Stablesend gốc)

| Hàm | Việc | Kịch bản demo |
|---|---|---|
| `payTo` | Trả trực tiếp có memo | Thanh toán 1-1 kèm nội dung |
| `batchPay` | Chi N người trong 1 tx | Chi cước tài xế tháng 6/2026 |
| `createRequest` / `payRequest` | Hóa đơn on-chain | Khách Hàn thanh toán invoice cước KR→VN |

Giữ nguyên từ Stablesend: pull-payment, `withdraw`, handle registry
(`tramcrypto68`), fee cap cứng 5%, ReentrancyGuard, SafeERC20, custom errors.

## Kiến trúc

```
Payer (Privy wallet) --approve--> USDC
      |
      | payTo / batchPay / payRequest
      v
StablesendPay.sol  (Arc Testnet, Chain ID 5042002)
      |  ledger nội bộ (pull-payment)
      v
Recipient --withdraw--> ví
```

## Trạng thái hiện tại

- [x] Contract `StablesendPay.sol` — compile sạch (Solc 0.8.24, OZ 5.1)
- [x] 14/14 test Foundry PASS (payTo, batchPay, request, fee cap, withdraw, handle)
- [x] Deploy script cho Arc Testnet
- [x] Component `BatchPayForm.tsx` (trang /batch)
- [ ] Deploy testnet + lưu tx hash trên explorer
- [ ] Ghép /pay, /request/[id] vào frontend Stablesend cũ
- [ ] Video demo 2–3 phút
- [ ] Nộp qua Encode Platform

## Kế hoạch nộp (đường nhanh, ~2 tuần)

**Tuần 1**
1. `forge test` (đã xanh) → deploy testnet → verify, lưu tx hash.
2. Ghép 3 trang vào frontend Stablesend cũ: `/pay`, `/batch`, `/request/[id]`.
3. Chuẩn bị 2–3 hóa đơn cước ẩn danh làm dữ liệu demo thật.

**Tuần 2**
4. Quay demo: kể bài toán logistics → show `batchPay` chi 3 tài xế trong 1 tx → settle dưới 1 giây trên Arc explorer.
5. Cập nhật README (problem → solution → architecture → run).
6. Nộp: repo + link deploy + video + pitch.

## Lệnh nhanh

```bash
forge test -vv                         # chạy test
forge script script/DeployStablesendPay.s.sol \
  --rpc-url https://rpc.testnet.arc.network --broadcast -vvvv
```
