#!/data/data/com.termux/files/usr/bin/bash
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}[*] Installing Python...${NC}"
command -v python >/dev/null 2>&1 || pkg install python -y

echo -e "${CYAN}[*] Setting up project...${NC}"
mkdir -p ~/otp-sec-tool/{core,data/reports,samples}
cd ~/otp-sec-tool
touch core/__init__.py

cat > config.py << 'EOF'
APP_NAME = "Multi-Method OTP Security Testing Tool"
APP_VERSION = "1.0.0"
SIM_DELAY_MIN = 0.15
SIM_DELAY_MAX = 0.45
REPORTS_DIR = "data/reports"
NUMBERS_FILE = "data/numbers.txt"
CATEGORIES = {
    "login": "Login Verification",
    "register": "Registration Verification",
    "recovery": "Password Recovery Verification",
}
EOF

cat > core/colors.py << 'EOF'
class C:
    RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
    RED="\033[91m"; GREEN="\033[92m"; YELLOW="\033[93m"
    CYAN="\033[96m"; MAGENTA="\033[95m"
def ok(m): return f"{C.GREEN}{m}{C.RESET}"
def err(m): return f"{C.RED}{m}{C.RESET}"
def warn(m): return f"{C.YELLOW}{m}{C.RESET}"
def info(m): return f"{C.CYAN}{m}{C.RESET}"
def bold(m): return f"{C.BOLD}{m}{C.RESET}"
def dim(m): return f"{C.DIM}{m}{C.RESET}"
def mag(m): return f"{C.MAGENTA}{m}{C.RESET}"
EOF

cat > core/banner.py << 'EOF'
import sys
from core.colors import C, bold, dim
BANNER = r"""
   ____  _____ ____     ____            _
  / __ \|  _ \|  _ \   / ___|  ___  ___(_) __ _
 | |  | | |_) | |_) |  \___ \ / _ \/ __| |/ _` |
 | |__| |  __/|  __/    ___) |  __/ (__| | (_| |
  \____/|_|   |_|      |____/ \___|\___|_|\__,_|
"""
def show_banner():
    print(C.CYAN + BANNER + C.RESET)
    print(bold("  Multi-Method OTP Security Testing Tool  v1.0.0"))
    print(dim("  Ethical Security Testing - Mock Environment Only"))
    print(dim("  " + "-" * 52))
def sep(char="-", n=54): print(dim(char * n))
def progress_bar(current, total, width=30, label=""):
    if total == 0: return
    ratio = current / total; filled = int(width * ratio)
    bar = "#" * filled + "-" * (width - filled); pct = int(ratio * 100)
    sys.stdout.write(f"\r{C.CYAN}{label} |{bar}| {pct:3d}%{C.RESET}")
    sys.stdout.flush()
    if current == total: sys.stdout.write("\n")
EOF

cat > core/validator.py << 'EOF'
import re
NUM_RE = re.compile(r"^\+?\d{7,15}$")
def is_valid_number(num): return bool(NUM_RE.match(num.strip()))
def normalize(num):
    n = num.strip().replace(" ", "").replace("-", "")
    if not n.startswith("+"): n = "+" + n
    return n
EOF

cat > core/number_manager.py << 'EOF'
import os
from config import NUMBERS_FILE
from core.colors import C, ok, err, warn, info, bold
from core.validator import is_valid_number, normalize
class NumberManager:
    def __init__(self):
        self._numbers = []
        os.makedirs(os.path.dirname(NUMBERS_FILE), exist_ok=True)
    def add_manual(self):
        print(info("\n  Enter numbers (comma-separated):"))
        raw = input(f"  {C.CYAN}> {C.RESET}").strip()
        if not raw: print(warn("  Cancelled.")); return
        added = rejected = 0
        for p in [x for x in raw.replace(" ", "").split(",") if x]:
            if is_valid_number(p):
                n = normalize(p)
                if n not in self._numbers: self._numbers.append(n); added += 1
            else: rejected += 1
        print(ok(f"  OK Added: {added}") + (f"   {err(f'Rejected: {rejected}')}" if rejected else ""))
    def import_file(self):
        path = input(f"  {C.CYAN}File path > {C.RESET}").strip()
        if not os.path.isfile(path): print(err(f"  File not found: {path}")); return
        added = rejected = 0
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"): continue
                    if is_valid_number(line):
                        n = normalize(line)
                        if n not in self._numbers: self._numbers.append(n); added += 1
                    else: rejected += 1
            print(ok(f"  OK Imported: {added}") + (f"   {err(f'Rejected: {rejected}')}" if rejected else ""))
        except Exception as e: print(err(f"  Error: {e}"))
    def view(self):
        if not self._numbers: print(warn("  No numbers loaded.")); return
        print(bold(f"\n  Imported Numbers ({len(self._numbers)}):"))
        for i, n in enumerate(self._numbers, 1): print(f"  {C.CYAN}{i:>3}.{C.RESET} {n}")
    def clear(self):
        n = len(self._numbers); self._numbers.clear()
        print(ok(f"  Cleared {n} number(s)."))
    def get(self): return list(self._numbers)
    def count(self): return len(self._numbers)
EOF

cat > core/mock_api.py << 'EOF'
import hashlib
class MockOTPAPI:
    def __init__(self, seed=42): self.seed = seed
    def _fp(self, number, category):
        h = hashlib.sha256(f"{self.seed}:{number}:{category}".encode()).hexdigest()
        return int(h[:8], 16)
    def request_otp(self, number, category):
        fp = self._fp(number, category); b = fp % 100
        if b < 55: return {"status":"SUCCESS","code":200,"message":"Mock OTP issued","latency_ms":90+fp%60}
        if b < 75: return {"status":"RATE_LIMITED","code":429,"message":"Mock rate limit","latency_ms":40+fp%30}
        if b < 88: return {"status":"INVALID_NUMBER","code":400,"message":"Mock rejected","latency_ms":25}
        if b < 95: return {"status":"SERVER_ERROR","code":500,"message":"Mock server error","latency_ms":200}
        return {"status":"TIMEOUT","code":0,"message":"Mock timeout","latency_ms":1500}
EOF

cat > core/tester.py << 'EOF'
import time, random
from config import CATEGORIES, SIM_DELAY_MIN, SIM_DELAY_MAX
from core.colors import C, ok, err, warn, info, bold, dim, mag
from core.mock_api import MockOTPAPI
from core.banner import progress_bar
class TestResult:
    def __init__(self, tid, method, number, status, http_code, latency, message, error=None, ts=None):
        self.tid=tid; self.method=method; self.number=number; self.status=status
        self.http_code=http_code; self.latency=latency; self.message=message
        self.error=error; self.timestamp=ts or time.time()
    def to_dict(self):
        return {k:getattr(self,k) for k in ["tid","method","number","status","http_code","latency","message","error","timestamp"]}
class Tester:
    def __init__(self):
        self.api = MockOTPAPI(); self.results = []; self._counter = 0
        self._rng = random.Random(7)
    def _nid(self): self._counter += 1; return f"TEST-{self._counter:03d}"
    def _color(self, s):
        if s == "SUCCESS": return ok(s)
        if s in ("RATE_LIMITED","TIMEOUT"): return warn(s)
        return err(s)
    def _run_one(self, number, cat):
        method = CATEGORIES[cat]; tid = self._nid()
        try:
            r = self.api.request_otp(number, cat)
            res = TestResult(tid, method, number, r["status"], r["code"], r["latency_ms"], r["message"])
        except Exception as e:
            res = TestResult(tid, method, number, "ERROR", 0, 0, "Exception", str(e))
        self.results.append(res)
        print(f"\n  {mag('['+tid+']')} {bold(method)}")
        print(f"    Number : {info(number)}")
        print(f"    Status : {self._color(res.status)}  (HTTP {res.http_code})")
        print(f"    Latency: {res.latency} ms")
        print(f"    Msg    : {dim(res.message)}")
        return res
    def run_category(self, cat, numbers):
        if not numbers: print(warn("  No numbers loaded.")); return
        print(bold(f"\n  >> Running {CATEGORIES[cat]} on {len(numbers)} number(s)..."))
        for i, n in enumerate(numbers, 1):
            self._run_one(n, cat)
            progress_bar(i, len(numbers), label="  Progress")
            time.sleep(self._rng.uniform(SIM_DELAY_MIN, SIM_DELAY_MAX))
    def run_all(self, numbers):
        if not numbers: print(warn("  No numbers loaded.")); return
        total = len(numbers) * len(CATEGORIES); done = 0
        print(bold(f"\n  >> Running ALL categories ({total} tests)..."))
        for cat in CATEGORIES:
            print(info(f"\n  -- {CATEGORIES[cat]} --"))
            for n in numbers:
                self._run_one(n, cat); done += 1
                progress_bar(done, total, label="  Overall ")
                time.sleep(self._rng.uniform(SIM_DELAY_MIN, SIM_DELAY_MAX))
    def all_results(self): return list(self.results)
EOF

cat > core/reporter.py << 'EOF'
import os, json, time
from datetime import datetime
from config import REPORTS_DIR
from core.colors import C, ok, err, warn, info, bold, dim
class Reporter:
    def __init__(self, results, numbers_count=0, start_ts=None):
        self.results = results; self.numbers_count = numbers_count
        self.start_ts = start_ts or time.time()
    def _summary(self):
        total = len(self.results)
        success = sum(1 for r in self.results if r.status == "SUCCESS")
        pending = sum(1 for r in self.results if r.status in ("RATE_LIMITED","TIMEOUT"))
        failed = total - success - pending
        by_method = {}
        for r in self.results:
            m = by_method.setdefault(r.method, {"total":0,"ok":0,"fail":0})
            m["total"] += 1
            if r.status == "SUCCESS": m["ok"] += 1
            else: m["fail"] += 1
        return {"total":total,"success":success,"failed":failed,"pending":pending,
                "duration_sec":round(time.time()-self.start_ts,2),
                "numbers_loaded":self.numbers_count,"by_method":by_method,
                "timestamp":datetime.now().isoformat(timespec="seconds")}
    def print_summary(self):
        s = self._summary()
        print(bold("\n  SUMMARY REPORT"))
        print(f"  Total tests     : {info(str(s['total']))}")
        print(f"  Successful      : {ok(str(s['success']))}")
        print(f"  Failed          : {err(str(s['failed']))}")
        print(f"  Pending/Warn    : {warn(str(s['pending']))}")
        print(f"  Execution time  : {info(str(s['duration_sec'])+'s')}")
        print(f"  Environment     : {dim('mock:// local simulated')}")
    def export_json(self):
        os.makedirs(REPORTS_DIR, exist_ok=True)
        path = os.path.join(REPORTS_DIR, f"report_{int(time.time())}.json")
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"meta":self._summary(),"results":[r.to_dict() for r in self.results]}, f, indent=2, ensure_ascii=False)
            print(ok(f"  OK JSON report -> {path}"))
        except Exception as e: print(err(f"  Export failed: {e}"))
    def export_html(self):
        os.makedirs(REPORTS_DIR, exist_ok=True)
        path = os.path.join(REPORTS_DIR, f"report_{int(time.time())}.html")
        s = self._summary(); rows = ""
        for r in self.results:
            color = "#16a34a" if r.status == "SUCCESS" else "#d97706" if r.status in ("RATE_LIMITED","TIMEOUT") else "#dc2626"
            rows += f"<tr><td>{r.tid}</td><td>{r.method}</td><td>{r.number}</td><td style='color:{color};font-weight:bold'>{r.status}</td><td>{r.http_code}</td><td>{r.latency}ms</td><td>{r.message}</td></tr>"
        html = f"<!DOCTYPE html><html><head><meta charset='utf-8'><title>OTP Test Report</title><style>body{{font-family:sans-serif;background:#0f172a;color:#e2e8f0;padding:24px}}h1{{color:#38bdf8}}table{{width:100%;border-collapse:collapse;margin-top:16px}}th,td{{padding:8px;border-bottom:1px solid #334155;text-align:left}}th{{background:#1e293b;color:#38bdf8}}</style></head><body><h1>OTP Security Test Report</h1><p>Success: {s['success']} | Failed: {s['failed']} | Total: {s['total']} | Duration: {s['duration_sec']}s</p><table><thead><tr><th>ID</th><th>Method</th><th>Number</th><th>Status</th><th>HTTP</th><th>Latency</th><th>Message</th></tr></thead><tbody>{rows}</tbody></table></body></html>"
        try:
            with open(path, "w", encoding="utf-8") as f: f.write(html)
            print(ok(f"  OK HTML report -> {path}"))
        except Exception as e: print(err(f"  HTML export failed: {e}"))
EOF

cat > main.py << 'EOF'
import sys, time
from core.colors import C, ok, err, warn, info, bold
from core.banner import show_banner, sep
from core.number_manager import NumberManager
from core.tester import Tester
from core.reporter import Reporter
class App:
    def __init__(self):
        self.nm = NumberManager(); self.tester = Tester(); self.start_ts = time.time()
    def menu(self):
        sep(); print(bold("  MAIN MENU")); sep()
        for k, v in [("1","Import Number File"),("2","Enter Numbers Manually"),("3","View Imported Data"),
                     ("4","Login Verification Tests"),("5","Registration Verification Tests"),
                     ("6","Password Recovery Tests"),("7","Run All Tests"),("8","View Test Results"),
                     ("9","Export Report"),("C","Clear Imported Numbers"),("0","Exit")]:
            print(f"  {C.CYAN}[{k}]{C.RESET} {v}")
        sep()
    def view_results(self):
        res = self.tester.all_results()
        if not res: print(warn("  No test results yet.")); return
        print(bold(f"\n  Test Results ({len(res)}):")); sep()
        for r in res:
            tag = ok(r.status) if r.status == "SUCCESS" else warn(r.status) if r.status in ("RATE_LIMITED","TIMEOUT") else err(r.status)
            print(f"  [{C.MAGENTA}{r.tid}{C.RESET}] {r.method:<32} {r.number:<16} {tag}")
    def export(self):
        if not self.tester.all_results(): print(warn("  Nothing to export yet.")); return
        rep = Reporter(self.tester.all_results(), self.nm.count(), self.start_ts)
        rep.print_summary(); rep.export_json(); rep.export_html()
    def run(self):
        show_banner()
        while True:
            try:
                self.menu()
                ch = input(f"  {C.CYAN}Select > {C.RESET}").strip().upper()
                if ch == "1": self.nm.import_file()
                elif ch == "2": self.nm.add_manual()
                elif ch == "3": self.nm.view()
                elif ch == "4": self.tester.run_category("login", self.nm.get())
                elif ch == "5": self.tester.run_category("register", self.nm.get())
                elif ch == "6": self.tester.run_category("recovery", self.nm.get())
                elif ch == "7": self.tester.run_all(self.nm.get())
                elif ch == "8": self.view_results()
                elif ch == "9": self.export()
                elif ch == "C": self.nm.clear()
                elif ch == "0": print(info("\n  Goodbye!\n")); return
                else: print(err("  Invalid choice."))
            except KeyboardInterrupt: print(warn("\n  Interrupted.")); return
            except Exception as e: print(err(f"  Error: {e}")); continue
if __name__ == "__main__":
    try: App().run()
    except Exception as e: print(f"Fatal: {e}"); sys.exit(1)
EOF

cat > samples/numbers.txt << 'EOF'
+8801700000001
+8801700000002
+8801700000003
+15551234567
+447700900123
+919876543210
EOF

cat > ~/otp-tool << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/otp-sec-tool && python main.py
EOF
chmod +x ~/otp-tool

if ! grep -q "alias otp-tool" ~/.bashrc 2>/dev/null; then
    echo "alias otp-tool='~/otp-tool'" >> ~/.bashrc
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${CYAN}Run with:${NC}  otp-tool"
echo ""