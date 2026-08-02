"use client";

/**
 * BatchPayForm — new page for StablesendPay (/batch)
 *
 * Paste rows of "address,amount,memo" (e.g. exported from a driver/vendor
 * payout sheet), approve USDC once, then disburse to everyone in a single
 * transaction on Arc. This is the treasury-track demo: one tx pays N people.
 *
 * Stack: Next.js 14 + wagmi v2 + viem. USDC has 6 decimals.
 */

import { useMemo, useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { parseUnits, erc20Abi, type Address } from "viem";

const PAY_ADDRESS = process.env.NEXT_PUBLIC_STABLESEND_PAY as Address;
const USDC_ADDRESS = "0x3600000000000000000000000000000000000000" as Address;

// Minimal ABI slice for the functions this page calls.
const payAbi = [
  {
    type: "function",
    name: "batchPay",
    stateMutability: "nonpayable",
    inputs: [
      { name: "recipients", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
      { name: "memo", type: "string" },
    ],
    outputs: [],
  },
] as const;

type Row = { to: Address; amount: bigint; raw: string };

function parseRows(text: string): { rows: Row[]; errors: string[] } {
  const rows: Row[] = [];
  const errors: string[] = [];
  text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .forEach((line, i) => {
      const [addr, amt] = line.split(",").map((s) => s?.trim());
      if (!addr?.startsWith("0x") || addr.length !== 42) {
        errors.push(`Dòng ${i + 1}: địa chỉ không hợp lệ`);
        return;
      }
      if (!amt || Number.isNaN(Number(amt))) {
        errors.push(`Dòng ${i + 1}: số tiền không hợp lệ`);
        return;
      }
      rows.push({ to: addr as Address, amount: parseUnits(amt, 6), raw: line });
    });
  return { rows, errors };
}

export default function BatchPayForm() {
  const { isConnected } = useAccount();
  const { writeContractAsync, isPending } = useWriteContract();
  const [text, setText] = useState("");
  const [memo, setMemo] = useState("");
  const [status, setStatus] = useState<string>("");

  const { rows, errors } = useMemo(() => parseRows(text), [text]);
  const total = useMemo(() => rows.reduce((a, r) => a + r.amount, 0n), [rows]);
  const totalHuman = (Number(total) / 1e6).toLocaleString();

  async function handlePayout() {
    if (rows.length === 0 || errors.length > 0) return;
    try {
      setStatus("Đang approve USDC…");
      await writeContractAsync({
        address: USDC_ADDRESS,
        abi: erc20Abi,
        functionName: "approve",
        args: [PAY_ADDRESS, total],
      });

      setStatus("Đang chi hàng loạt…");
      const hash = await writeContractAsync({
        address: PAY_ADDRESS,
        abi: payAbi,
        functionName: "batchPay",
        args: [rows.map((r) => r.to), rows.map((r) => r.amount), memo],
      });
      setStatus(`Xong! Tx: ${hash}`);
    } catch (e: any) {
      setStatus(`Lỗi: ${e?.shortMessage ?? e?.message ?? "unknown"}`);
    }
  }

  return (
    <div className="mx-auto max-w-xl space-y-4 p-6">
      <h1 className="text-2xl font-bold">Batch Payout · USDC trên Arc</h1>
      <p className="text-sm text-gray-500">
        Dán mỗi dòng: <code>địa_chỉ,số_tiền</code>. Approve 1 lần, chi cho tất cả
        trong 1 giao dịch.
      </p>

      <textarea
        className="h-40 w-full rounded-lg border p-3 font-mono text-sm"
        placeholder={"0xabc...,50\n0xdef...,150"}
        value={text}
        onChange={(e) => setText(e.target.value)}
      />

      <input
        className="w-full rounded-lg border p-3 text-sm"
        placeholder="Ghi chú (vd: Chi cước tài xế tháng 6/2026)"
        value={memo}
        onChange={(e) => setMemo(e.target.value)}
        maxLength={280}
      />

      <div className="flex items-center justify-between text-sm">
        <span>
          {rows.length} người nhận · Tổng <strong>{totalHuman} USDC</strong>
        </span>
        {errors.length > 0 && (
          <span className="text-red-500">{errors.length} dòng lỗi</span>
        )}
      </div>

      {errors.length > 0 && (
        <ul className="text-xs text-red-500">
          {errors.map((e, i) => (
            <li key={i}>{e}</li>
          ))}
        </ul>
      )}

      <button
        className="w-full rounded-lg bg-black py-3 font-semibold text-white disabled:opacity-40"
        disabled={!isConnected || isPending || rows.length === 0 || errors.length > 0}
        onClick={handlePayout}
      >
        {isPending ? "Đang xử lý…" : `Chi ${totalHuman} USDC cho ${rows.length} người`}
      </button>

      {status && <p className="break-all text-xs text-gray-600">{status}</p>}
    </div>
  );
}
