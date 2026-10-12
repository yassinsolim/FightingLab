import os, sys, time, urllib.request, concurrent.futures as cf
m = sys.argv[1]
raw = os.path.join(m, "raw", "cmu")
trials = """13_17 13_18 14_01 14_02 14_03 15_13 17_10 79_08 80_10 02_05
86_01 86_06 86_08 141_14 143_23 143_24 113_13
144_05 144_06 144_07 144_08 144_09 144_10 144_13 144_14 144_20 144_21 144_26 144_27 144_11 144_17
135_01 135_02 135_03 135_04 135_05 135_06 135_07 135_09 135_10 135_11
74_03 74_04 74_05 74_06 75_16 87_01 88_06 90_05 90_06 90_07 88_04
76_01 76_02 76_03 76_04 76_09 76_11
77_03 77_09 77_16 77_17 77_18
90_16 90_17 90_18 85_15 85_07 91_59 22_12 23_12
140_01 140_02 140_03 140_04 140_08 140_09 140_06 140_07 139_16 139_17 139_18 139_09
83_01 83_04 83_13 83_14 83_16 83_19 83_33 83_55 83_66 83_68 83_40 83_48
102_22 102_23 102_27 102_28 78_29
69_39 136_25 141_31 136_09 136_11
79_69 80_43 79_94 79_74 79_71 56_03""".split()
jobs = []
subs = sorted({t.split("_")[0] for t in trials})
for s in subs:
    jobs.append((f"http://mocap.cs.cmu.edu/subjects/{s}/{s}.asf", os.path.join(raw, s, f"{s}.asf")))
for t in trials:
    s = t.split("_")[0]
    jobs.append((f"http://mocap.cs.cmu.edu/subjects/{s}/{t}.amc", os.path.join(raw, s, f"{t}.amc")))
def fetch(job):
    url, path = job
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return (path, os.path.getsize(path), "cached")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = r.read()
            if len(data) < 500 or b"<html" in data[:200].lower():
                raise RuntimeError(f"bad content {len(data)}")
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)
            return (path, len(data), "ok")
        except Exception as e:
            err = e
            time.sleep(2 + attempt * 3)
    return (path, 0, f"FAIL {err}")
t0 = time.time()
tot = 0
with cf.ThreadPoolExecutor(8) as ex:
    for path, n, st in ex.map(fetch, jobs):
        tot += n
        if st.startswith("FAIL"):
            print(st, path, flush=True)
print(f"done {len(jobs)} files, {tot/1e6:.1f} MB, {time.time()-t0:.0f}s", flush=True)
