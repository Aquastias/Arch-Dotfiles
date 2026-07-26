#!/usr/bin/env python3
# =============================================================================
# tools/guided-fzf-smoke.py — automated live-fzf render gate (issue 09 AC5)
# =============================================================================
# The persistent-fzf guided menu (ADR 0042) can only be eyeballed by a human,
# because fzf draws to a real tty. This drives tools/guided-preview.sh inside a
# PTY, sends keystrokes, and asserts the ISSUE-09 screens render the way a human
# would see them — so the "live fzf render + re-entry" HITL becomes a repeatable
# check. It runs NONE of the install flow (guided-preview.sh is inert), so it is
# safe on any machine. Requires fzf on PATH.
#
#   python3 .os/tools/guided-fzf-smoke.py     # exit 0 = all screens rendered OK
#
# Coverage: the top menu draws (no flash to bare shell); the root-fs picker lists
# all four built adapters with no "(reserved)"; the Disks screen shows the
# impermanence row for a zfs root but HIDES it for an ext4 root; the data-pool
# editor renders the per-group filesystem/topology/encryption rows.
import os, pty, select, subprocess, sys, time, re, fcntl, termios, struct

OS_DIR = os.environ.get("OS_DIR") or os.path.abspath(
    os.path.join(os.path.dirname(__file__), ".."))
PREVIEW = os.path.join(OS_DIR, "tools/guided-preview.sh")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][AB0]|\x1b[=>]|\r")
strip = lambda b: ANSI.sub("", b.decode("utf-8", "replace"))

results = []
def check(name, cond):
    results.append(cond)
    print(f"[{'PASS' if cond else 'FAIL'}] {name}")

class Session:
    """A guided-preview.sh instance on its own PTY."""
    def __init__(self):
        self.master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.p = subprocess.Popen(
            ["bash", PREVIEW], stdin=slave, stdout=slave, stderr=slave,
            preexec_fn=os.setsid,
            env={**os.environ, "TERM": "xterm-256color", "SHELL": "/bin/bash"})
        os.close(slave)
        self.buf = bytearray()

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.master], [], [], 0.2)
            if self.master in r:
                try:
                    d = os.read(self.master, 65536)
                except OSError:
                    break
                if not d:
                    break
                self.buf.extend(d)

    def send(self, s):
        os.write(self.master, s.encode())

    def enter(self, query, settle=0.4):
        """Type a filter query, then Enter (fzf selects the filtered row)."""
        self.send(query); time.sleep(settle); self.send("\r")

    def screen(self):
        return strip(bytes(self.buf))

    def clear(self):
        self.buf.clear()

    def quit(self):
        self.send("\x03"); time.sleep(0.2)
        try:
            os.killpg(os.getpgid(self.p.pid), 15)
        except Exception:
            pass


def word(text, w):
    return re.search(rf"\b{re.escape(w)}\b", text) is not None


# ── root-fs picker + impermanence shown for a zfs root ───────────────────────
s = Session()
s.pump(3.0)
top = s.screen()
check("top menu renders (Disks visible, no flash to bare shell)",
      "Disks" in top and ("Enter open" in top or "undo" in top))
s.clear()
s.enter("Disks"); s.pump(2.0)
disks = s.screen()
check("Disks screen shows the filesystem row", "filesystem" in disks)
check("zfs root: the impermanence row is shown", "impermanence" in disks)
s.clear()
s.enter("filesystem"); s.pump(2.0)
fs = s.screen()
for name in ("zfs", "btrfs", "ext4", "xfs"):
    check(f"root-fs picker lists '{name}'", word(fs, name))
check("root-fs picker has no '(reserved)' marker", "reserved" not in fs.lower())
s.quit()

# ── data-pool editor renders the per-group filesystem/encryption rows ────────
s = Session()
s.pump(3.0); s.clear()
s.enter("Disks"); s.pump(2.0); s.clear()
s.enter("layout"); s.pump(2.0); s.clear()
s.enter("data-pools"); s.pump(2.0); s.clear()
s.enter("tank0"); s.pump(2.0)
pool = s.screen()
check("pool editor renders a 'filesystem:' row", "filesystem:" in pool)
check("pool editor renders a 'topology:' row", "topology:" in pool)
check("pool editor renders an 'encryption:' row", "encryption:" in pool)
s.quit()

# ── impermanence row is HIDDEN under an ext4 root ────────────────────────────
s = Session()
s.pump(3.0); s.clear()
s.enter("Disks"); s.pump(2.0); s.clear()
s.enter("filesystem"); s.pump(2.0); s.clear()
s.enter("ext4"); s.pump(2.0)   # commit ext4 → returns to the Disks category
disks = s.screen()
check("ext4 root: Disks shows 'filesystem: ext4'", "ext4" in disks)
check("ext4 root: the impermanence row is hidden", "impermanence" not in disks)
s.quit()

# ── Users: inline masked password entry renders bullets, not plaintext ───────
# (ADR 0051) Navigate top → Users (flattened) → the root-password row, type a
# secret, and assert the query renders as bullets with the plaintext never shown.
s = Session()
s.pump(3.0); s.clear()
s.enter("Users"); s.pump(2.0); s.clear()
s.enter("root"); s.pump(2.0)          # open the inline masked secret screen
s.clear()
s.send("s3cret!"); s.pump(1.2)
sec = s.screen()
check("inline pw: the masked screen is reached (password prompt)",
      "password>" in sec)
check("inline pw: the query renders as bullets, not plaintext",
      ("•" * 7) in sec and "s3cret!" not in sec)
s.quit()

# ── Profiles picker: the top-screen row drills to the profile list (ADR 0055) ─
# Navigate top → Profiles and assert the drill screen lists the committed
# desktop/laptop profiles. guided-preview.sh points OS_DIR at the real repo, so
# hosts/{desktop,laptop} are the profiles enumerated.
s = Session()
s.pump(3.0)
top = s.screen()
check("top menu shows the Profiles row", "Profiles" in top)
s.clear()
s.enter("Profiles"); s.pump(2.0)
prof = s.screen()
check("Profiles screen lists desktop + laptop",
      "desktop" in prof and "laptop" in prof)
s.quit()

ok = all(results)
print(f"\n{sum(results)}/{len(results)} checks passed —",
      "ALL PASS" if ok else "FAILURES PRESENT")
sys.exit(0 if ok else 1)
