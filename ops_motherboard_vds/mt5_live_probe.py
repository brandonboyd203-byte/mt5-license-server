#!/usr/bin/env python3
import datetime
import glob
import json
import os
import tempfile
import time

try:
    import MetaTrader5 as mt5
except Exception as exc:
    payload = {
        "ok": False,
        "error": f"MetaTrader5 import failed: {exc}",
        "generatedAt": datetime.datetime.utcnow().isoformat() + "Z",
        "profiles": [],
    }
    out_path = r"C:\\GoldmineOps\\reports\\mt5_live_probe.json"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
    raise

REPORT_PATH = r"C:\\GoldmineOps\\reports\\mt5_live_probe.json"
MT5_GLOB = r"C:\\MT5\\*"
ACCOUNTS_CSV = r"C:\\GoldmineOps\\secure\\vds_accounts.csv"
SKIP_PROFILES = {"Base", "Presets"}
SKIP_PREFIXES = ("BLUEPRINT_TF_",)
PERTH_TZ = datetime.timezone(datetime.timedelta(hours=8))
DAY_START_HOUR_PERTH = 8


def utc_now():
    return datetime.datetime.utcnow().isoformat() + "Z"


def perth_day_start_utc(now_utc=None):
    now_utc = now_utc or datetime.datetime.now(datetime.timezone.utc)
    perth_now = now_utc.astimezone(PERTH_TZ)
    day_start_perth = perth_now.replace(
        hour=DAY_START_HOUR_PERTH,
        minute=0,
        second=0,
        microsecond=0,
    )
    if perth_now < day_start_perth:
        day_start_perth = day_start_perth - datetime.timedelta(days=1)
    return day_start_perth.astimezone(datetime.timezone.utc)


def text_lower(value):
    return str(value or "").strip().lower()


def should_skip_profile(profile_name):
    name = str(profile_name or "").strip()
    if not name:
        return True
    if name in SKIP_PROFILES:
        return True
    return any(name.startswith(prefix) for prefix in SKIP_PREFIXES)


def deal_cashflow_bucket(deal):
    amt = float(getattr(deal, "profit", 0.0) or 0.0)
    if abs(amt) < 1e-9:
        return None

    comment = text_lower(getattr(deal, "comment", ""))
    ext = text_lower(getattr(deal, "external_id", ""))
    note = f"{comment} {ext}"
    t = int(getattr(deal, "type", -1))
    candidate_types = set()
    for key in (
        "DEAL_TYPE_BALANCE",
        "DEAL_TYPE_CREDIT",
        "DEAL_TYPE_CHARGE",
        "DEAL_TYPE_CORRECTION",
        "DEAL_TYPE_BONUS",
    ):
        v = getattr(mt5, key, None)
        if v is not None:
            try:
                candidate_types.add(int(v))
            except Exception:
                pass

    if t not in candidate_types:
        return None

    if any(k in note for k in ("withdraw", "payout", "cashout")):
        return "withdraw"
    if any(k in note for k in ("deposit", "credit", "topup", "top-up", "top up")):
        return "deposit"
    return "deposit" if amt > 0 else "withdraw"


def deal_balance_impact(deal):
    profit = float(getattr(deal, "profit", 0.0) or 0.0)
    commission = float(getattr(deal, "commission", 0.0) or 0.0)
    swap = float(getattr(deal, "swap", 0.0) or 0.0)
    fee = float(getattr(deal, "fee", 0.0) or 0.0)
    return profit + commission + swap + fee


def load_target_profiles(csv_path):
    out = []
    if not os.path.exists(csv_path):
        return out
    try:
        with open(csv_path, "r", encoding="utf-8-sig") as fh:
            lines = [line.strip() for line in fh.readlines() if line.strip()]
        if len(lines) < 2:
            return out
        headers = [h.strip().lower() for h in lines[0].split(",")]
        p_idx = headers.index("profile") if "profile" in headers else -1
        a_idx = headers.index("account") if "account" in headers else -1
        if p_idx < 0:
            return out
        for line in lines[1:]:
            cols = [c.strip().strip('"') for c in line.split(",")]
            profile = cols[p_idx] if p_idx < len(cols) else ""
            account = cols[a_idx] if a_idx >= 0 and a_idx < len(cols) else ""
            if not profile:
                continue
            if should_skip_profile(profile):
                continue
            if account and account.isdigit():
                out.append(profile)
        return sorted(set(out))
    except Exception:
        return out


def probe_all_profiles():
    rows = []
    targets = load_target_profiles(ACCOUNTS_CSV)
    if targets:
        roots = [os.path.join(r"C:\\MT5", p) for p in targets if os.path.isdir(os.path.join(r"C:\\MT5", p))]
    else:
        roots = [
            p
            for p in glob.glob(MT5_GLOB)
            if os.path.isdir(p) and not should_skip_profile(os.path.basename(p))
        ]
    roots.sort()

    for root in roots:
        term = os.path.join(root, "terminal64.exe")
        if not os.path.exists(term):
            continue

        row = {
            "profile": os.path.basename(root),
            "path": root,
            "ok": False,
            "error": None,
            "account": None,
            "balance": None,
            "equity": None,
            "profit": None,
            "openPositions": None,
            "depositTotal": None,
            "withdrawTotal": None,
            "accountStartEquity": None,
            "dayStartEquity": None,
            "grossPnlClosed": None,
            "grossPnlWithOpen": None,
            "capturedAt": utc_now(),
            "durationMs": None,
        }

        started = time.time()
        try:
            ok = mt5.initialize(path=term, timeout=5000)
            if not ok:
                row["error"] = str(mt5.last_error())
                row["durationMs"] = int((time.time() - started) * 1000)
                rows.append(row)
                continue

            ai = mt5.account_info()
            pos = mt5.positions_get()
            deposits = 0.0
            withdrawals = 0.0
            day_balance_delta = 0.0
            now_utc = datetime.datetime.now(datetime.timezone.utc)
            from_day_utc = perth_day_start_utc(now_utc)
            try:
                from_dt = datetime.datetime(2010, 1, 1, tzinfo=datetime.timezone.utc)
                to_dt = now_utc
                deals = mt5.history_deals_get(from_dt, to_dt)
                if deals is None:
                    deals = []
                for d in deals:
                    bucket = deal_cashflow_bucket(d)
                    amt = float(getattr(d, "profit", 0.0) or 0.0)
                    if bucket == "deposit":
                        deposits += abs(amt)
                    elif bucket == "withdraw":
                        withdrawals += abs(amt)

                    t_sec = int(getattr(d, "time", 0) or 0)
                    if t_sec > 0:
                        d_utc = datetime.datetime.fromtimestamp(t_sec, tz=datetime.timezone.utc)
                        if d_utc >= from_day_utc:
                            day_balance_delta += deal_balance_impact(d)
            except Exception:
                # Keep probe resilient; telemetry continues even if history fetch fails.
                pass
            row["ok"] = True
            row["account"] = getattr(ai, "login", None)
            row["balance"] = float(getattr(ai, "balance", 0.0)) if ai else None
            row["equity"] = float(getattr(ai, "equity", 0.0)) if ai else None
            row["profit"] = float(getattr(ai, "profit", 0.0)) if ai else None
            row["openPositions"] = 0 if pos is None else len(pos)
            row["depositTotal"] = round(deposits, 2)
            row["withdrawTotal"] = round(withdrawals, 2)
            if deposits > 0 or withdrawals > 0:
                row["accountStartEquity"] = round(max(0.0, deposits), 2)
            elif row["balance"] is not None:
                row["accountStartEquity"] = round(float(row["balance"]), 2)
            if row["balance"] is not None:
                row["dayStartEquity"] = round(float(row["balance"]) - day_balance_delta, 2)
            if row["balance"] is not None:
                row["grossPnlClosed"] = round(float(row["balance"]) + withdrawals - deposits, 2)
            if row["equity"] is not None:
                row["grossPnlWithOpen"] = round(float(row["equity"]) + withdrawals - deposits, 2)
            row["durationMs"] = int((time.time() - started) * 1000)
            rows.append(row)
        except Exception as exc:
            row["error"] = str(exc)
            row["durationMs"] = int((time.time() - started) * 1000)
            rows.append(row)
        finally:
            try:
                mt5.shutdown()
            except Exception:
                pass

    return rows


def atomic_write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="mt5_live_probe_", suffix=".json", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def main():
    started = time.time()
    rows = probe_all_profiles()
    payload = {
        "ok": True,
        "generatedAt": utc_now(),
        "count": len(rows),
        "durationMs": int((time.time() - started) * 1000),
        "profiles": rows,
    }
    atomic_write_json(REPORT_PATH, payload)


if __name__ == "__main__":
    main()
