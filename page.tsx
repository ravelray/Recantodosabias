"use client";
import { useEffect, useState } from "react";
import { j, fmtDate } from "@/lib/client";

export default function Auditoria() {
  const [from, setFrom] = useState(""), [to, setTo] = useState(""), [user, setUser] = useState(""), [d, setD] = useState<any>(null), [err, setErr] = useState("");
  async function run() { try { setD(await j(`/api/audit?from=${from}&to=${to}&userId=${user}`)); } catch (e: any) { setErr(e.message); } }
  useEffect(() => { run(); }, []);
  return (
    <div><h1>Auditoria</h1>{err && <div className="err">{err}</div>}
      <div className="card"><div className="row"><div><label>De</label><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div><div><label>Até</label><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
        <div><label>Funcionário</label><select value={user} onChange={(e) => setUser(e.target.value)}><option value="">Todos</option>{d?.users?.map((u: any) => <option key={u.id} value={u.id}>{u.full_name}</option>)}</select></div></div>
        <button className="btn green" style={{ marginTop: 10 }} onClick={run}>Filtrar</button></div>
      <div className="card tablewrap"><table><thead><tr><th>Data</th><th>Funcionário</th><th>Ação</th><th>Item</th><th>IP</th></tr></thead><tbody>
        {d?.rows?.map((r: any) => <tr key={r.id}><td>{fmtDate(r.created_at)}</td><td>{r.who || "—"}</td><td>{r.action}</td><td>{r.entity}</td><td>{r.ip || ""}</td></tr>)}</tbody></table></div>
    </div>
  );
}
