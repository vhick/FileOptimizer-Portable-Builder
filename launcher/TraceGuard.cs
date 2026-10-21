// TraceGuard v1.2: conservative before/after evidence and narrow restoration.
// This is NOT a system-wide filesystem/registry event monitor. It inspects bounded, specified
// host locations and only relocates newly created, unmistakably FileOptimizer-named folders.
// All reports and recovered data remain within the portable Data directory.
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

internal sealed class TraceGuardSession
{
    private const string BrowserKey = @"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION";
    private static readonly string[] BrowserValues = { "FileOptimizer64.exe", "FileOptimizer32.exe" };
    private static readonly string[] OwnFolderNames = {
        "FileOptimizer", "FileOptimizer64", "FileOptimizer32", "FileOptimizer64.exe.WebView2", "FileOptimizer32.exe.WebView2"
    };
    private readonly string data, app, traceRoot, sessionId, backupFile;
    private readonly List<string> roots = new List<string>();
    private readonly Dictionary<string, string> before;
    private Dictionary<string, string> after;
    private readonly Dictionary<string, string> regBefore;
    private Dictionary<string, string> regAfter;
    private readonly List<string> report = new List<string>();
    private bool finished;

    public TraceGuardSession(string dataPath, string appPath)
    {
        data = Path.GetFullPath(dataPath);
        app = Path.GetFullPath(appPath);
        traceRoot = Path.Combine(data, "TraceGuard");
        Directory.CreateDirectory(traceRoot);
        sessionId = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6);
        backupFile = Path.Combine(traceRoot, "registry-recovery.bin");
        string roam = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string temp = Path.GetTempPath();
        AddRoot(roam); AddRoot(local);
        AddRoot(Path.Combine(Path.GetDirectoryName(local) ?? local, "LocalLow"));
        AddRoot(temp);
        AddRoot(app); // detects newly created, app-adjacent WebView2 profile folders
        RestorePreviousRegistrySession(backupFile, report);
        before = SnapshotFileSystem();
        regBefore = SnapshotRegistry();
        SaveRegistryRecovery(backupFile);
        report.Add("SESSION " + sessionId + " (UTC)");
        report.Add("MODE Targeted before/after comparison; not a full process attribution monitor.");
        report.Add("ROOTS " + String.Join("; ", roots.ToArray()));
    }

    private void AddRoot(string p)
    {
        if (String.IsNullOrEmpty(p)) return;
        string full;
        try { full = Path.GetFullPath(p).TrimEnd(Path.DirectorySeparatorChar); }
        catch { return; }
        if (!roots.Exists(x => String.Equals(x, full, StringComparison.OrdinalIgnoreCase))) roots.Add(full);
    }
    private static bool IsOwn(string name)
    {
        foreach (string x in OwnFolderNames) if (String.Equals(x, name, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }
    private static bool IsInteresting(string name)
    {
        return name.IndexOf("fileoptimizer", StringComparison.OrdinalIgnoreCase) >= 0 ||
               name.IndexOf("nikkho", StringComparison.OrdinalIgnoreCase) >= 0;
    }
    private static string Signature(string path, bool isDir)
    {
        try {
            if (isDir) return "DIRECTORY";
            FileInfo info = new FileInfo(path);
            return "FILE len=" + info.Length + " utc=" + info.LastWriteTimeUtc.Ticks;
        } catch { return "INACCESSIBLE"; }
    }
    private static void TakeNamedTree(string path, Dictionary<string, string> snapshot, int depth, int maximum)
    {
        if (snapshot.Count >= maximum || depth > 4) return;
        try {
            if (!Directory.Exists(path)) return;
            DirectoryInfo info = new DirectoryInfo(path);
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0) return;
            foreach (FileSystemInfo child in info.EnumerateFileSystemInfos()) {
                if (snapshot.Count >= maximum) return;
                bool dir = (child.Attributes & FileAttributes.Directory) != 0;
                snapshot[child.FullName] = Signature(child.FullName, dir);
                if (dir && (child.Attributes & FileAttributes.ReparsePoint) == 0) TakeNamedTree(child.FullName, snapshot, depth + 1, maximum);
            }
        } catch (UnauthorizedAccessException) { } catch (IOException) { }
    }
    private Dictionary<string, string> SnapshotFileSystem()
    {
        Dictionary<string, string> found = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string root in roots) {
            if (!Directory.Exists(root)) continue;
            try {
                // Top-level entries are inventory only; this detects unexpected additions for review.
                foreach (FileSystemInfo item in new DirectoryInfo(root).EnumerateFileSystemInfos()) {
                    if (found.Count >= 25000) break;
                    bool dir = (item.Attributes & FileAttributes.Directory) != 0;
                    found[item.FullName] = Signature(item.FullName, dir);
                    if (dir && IsInteresting(item.Name) && (item.Attributes & FileAttributes.ReparsePoint) == 0)
                        TakeNamedTree(item.FullName, found, 0, 25000);
                }
            } catch (UnauthorizedAccessException) { } catch (IOException) { }
        }
        // Settings that upstream may fall back to storing in %USERPROFILE%.
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        foreach (string name in new[] { "FileOptimizer.ini", "FileOptimizer.log", "FileOptimizer64.ini", "FileOptimizer64.log" }) {
            string p = Path.Combine(home, name);
            if (File.Exists(p)) found[p] = Signature(p, false);
        }
        return found;
    }
    private static string DigestRegistryValue(object value, RegistryValueKind kind)
    {
        // No secret registry value contents are written to the report.
        string str = value is byte[] ? Convert.ToBase64String((byte[])value) :
            value is string[] ? String.Join("\0", (string[])value) : Convert.ToString(value);
        using (SHA256 sha = SHA256.Create()) {
            return kind + ":" + BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(str ?? ""))).Replace("-", "");
        }
    }
    private static void EnumerateRegistry(string path, Dictionary<string, string> result, int depth)
    {
        if (depth > 3) return;
        try {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(path, false)) {
                if (key == null) return;
                result[path] = "KEY";
                foreach (string name in key.GetValueNames()) {
                    RegistryValueKind kind = key.GetValueKind(name);
                    result[path + "\\" + name] = DigestRegistryValue(key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames), kind);
                }
                foreach (string sub in key.GetSubKeyNames()) EnumerateRegistry(path + "\\" + sub, result, depth + 1);
            }
        } catch (Exception) { /* unavailable registry keys are reported by absence */ }
    }
    private Dictionary<string, string> SnapshotRegistry()
    {
        Dictionary<string, string> found = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        EnumerateRegistry(@"Software\FileOptimizer", found, 0);
        EnumerateRegistry(@"Software\Nikkho\FileOptimizer", found, 0);
        try {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(BrowserKey, false)) {
                if (key != null) foreach (string name in BrowserValues) {
                    if (Array.Exists(key.GetValueNames(), x => String.Equals(x, name, StringComparison.OrdinalIgnoreCase))) {
                        found[BrowserKey + "\\" + name] = DigestRegistryValue(key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames), key.GetValueKind(name));
                    }
                }
            }
        } catch (Exception) { }
        return found;
    }
    // BinaryWriter stores only the exact two application-specific browser-emulation values.
    // A marker survives crashes; another launch restores the previous host values first.
    private static void SaveRegistryRecovery(string filename)
    {
        string tmp = filename + ".writing";
        using (FileStream stream = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
        using (BinaryWriter w = new BinaryWriter(stream, Encoding.UTF8)) {
            w.Write("FileOptimizer-TraceGuard-Registry-v2");
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(BrowserKey, false)) {
                w.Write(k != null); // allows safe cleanup if this exact key was newly created
                foreach (string name in BrowserValues) {
                    w.Write(name);
                    bool exists = k != null && Array.Exists(k.GetValueNames(), x => String.Equals(x, name, StringComparison.OrdinalIgnoreCase));
                    w.Write(exists);
                    if (!exists) continue;
                    RegistryValueKind type = k.GetValueKind(name);
                    w.Write((int)type);
                    object value = k.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    if (type == RegistryValueKind.DWord) w.Write(Convert.ToInt32(value));
                    else if (type == RegistryValueKind.QWord) w.Write(Convert.ToInt64(value));
                    else if (type == RegistryValueKind.Binary) { byte[] b = (byte[])value; w.Write(b.Length); w.Write(b); }
                    else if (type == RegistryValueKind.MultiString) { string[] a=(string[])value; w.Write(a.Length); foreach (string s in a) w.Write(s); }
                    else w.Write(Convert.ToString(value) ?? "");
                }
            }
        }
        if (File.Exists(filename)) File.Delete(filename);
        File.Move(tmp, filename);
    }
    private static void RestorePreviousRegistrySession(string filename, List<string> log)
    {
        if (!File.Exists(filename)) return;
        // Do not discard recovery marker if registry access fails.
        try {
            using (FileStream stream = new FileStream(filename, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (BinaryReader r = new BinaryReader(stream, Encoding.UTF8)) {
                if (r.ReadString() != "FileOptimizer-TraceGuard-Registry-v2") throw new InvalidDataException("Unknown recovery format");
                bool keyExistedAtStart = r.ReadBoolean();
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(BrowserKey, true)) {
                    for (int i = 0; i < BrowserValues.Length; i++) {
                        string name = r.ReadString();
                        if (name != BrowserValues[i]) throw new InvalidDataException("Unexpected recovery value");
                        bool exists = r.ReadBoolean();
                        if (!exists) { if (key != null) key.DeleteValue(name, false); continue; }
                        RegistryValueKind kind = (RegistryValueKind)r.ReadInt32();
                        object value;
                        if (kind == RegistryValueKind.DWord) value = r.ReadInt32();
                        else if (kind == RegistryValueKind.QWord) value = r.ReadInt64();
                        else if (kind == RegistryValueKind.Binary) { int len=r.ReadInt32(); if (len > 1048576 || len < 0) throw new InvalidDataException("Invalid binary length"); value=r.ReadBytes(len); }
                        else if (kind == RegistryValueKind.MultiString) { int len=r.ReadInt32(); if (len > 1000 || len < 0) throw new InvalidDataException("Invalid list length"); string[] a = new string[len]; for(int j=0;j<len;j++) a[j]=r.ReadString(); value=a; }
                        else if (kind == RegistryValueKind.String || kind == RegistryValueKind.ExpandString) value = r.ReadString();
                        else throw new InvalidDataException("Unsupported registry value kind " + kind);
                        if (key == null) throw new InvalidOperationException("Original browser registry key is missing; cannot restore value " + name);
                        key.SetValue(name, value, kind);
                    }
                }
                if (!keyExistedAtStart) {
                    // Only remove our exact target key if the session created it AND it is still empty.
                    bool empty = false;
                    using (RegistryKey now = Registry.CurrentUser.OpenSubKey(BrowserKey, false)) {
                        empty = now != null && now.ValueCount == 0 && now.SubKeyCount == 0;
                    }
                    if (empty) {
                        Registry.CurrentUser.DeleteSubKey(BrowserKey, false);
                        log.Add("RECOVERY Removed newly created empty browser-emulation key.");
                    }
                }
            }
            File.Delete(filename);
            log.Add("RECOVERY Exact browser-emulation registry values restored from a previous session.");
        } catch (Exception e) { log.Add("RECOVERY WARNING " + e.Message); throw; }
    }
    private static bool HasReparsePoint(string folder)
    {
        try {
            foreach (string path in Directory.EnumerateFileSystemEntries(folder, "*", SearchOption.AllDirectories))
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return true;
            return false;
        } catch { return true; }
    }
    private static void VerifiedCopyAcrossVolumes(string from, string to)
    {
        // Only FileOptimizer-named, previously absent paths reach this function.
        // Do not delete the host copy unless every copied file is verified byte-for-byte.
        string[] files = Directory.GetFiles(from, "*", SearchOption.AllDirectories);
        if (files.Length > 10000) throw new IOException("Recovery exceeds file count safeguard (10000)");
        long bytes = 0;
        foreach (string f in files) { bytes += new FileInfo(f).Length; if (bytes > 512L * 1024 * 1024) throw new IOException("Recovery exceeds 512 MB safeguard"); }
        foreach (string dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories)) {
            string relative = dir.Substring(from.Length).TrimStart(Path.DirectorySeparatorChar);
            Directory.CreateDirectory(Path.Combine(to, relative));
        }
        Directory.CreateDirectory(to);
        using (SHA256 hash = SHA256.Create()) {
            foreach (string f in files) {
                string relative = f.Substring(from.Length).TrimStart(Path.DirectorySeparatorChar);
                string dst = Path.Combine(to, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(dst));
                File.Copy(f, dst, true);
                byte[] a, b;
                using (FileStream x = File.OpenRead(f)) a = hash.ComputeHash(x);
                using (FileStream x = File.OpenRead(dst)) b = hash.ComputeHash(x);
                if (!Convert.ToBase64String(a).Equals(Convert.ToBase64String(b), StringComparison.Ordinal))
                    throw new IOException("Recovery copy checksum mismatch. Host original retained: " + f);
            }
        }
        Directory.Delete(from, true);
    }
    private void RecoverNamedNewDirectories()
    {
        foreach (string root in roots) {
            if (!Directory.Exists(root)) continue;
            // Only direct children with exact, FileOptimizer-specific names, absent at session start.
            foreach (string folder in Directory.GetDirectories(root, "*", SearchOption.TopDirectoryOnly)) {
                string name = Path.GetFileName(folder);
                if (!IsOwn(name) || before.ContainsKey(folder)) continue;
                try {
                    if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0 || HasReparsePoint(folder)) {
                        report.Add("REVIEW (reparse point) " + folder); continue;
                    }
                    string destination = Path.Combine(traceRoot, "Recovered", sessionId, "Host-" + roots.IndexOf(root), name);
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    if (String.Equals(Path.GetPathRoot(folder), Path.GetPathRoot(destination), StringComparison.OrdinalIgnoreCase))
                        Directory.Move(folder, destination);
                    else VerifiedCopyAcrossVolumes(folder, destination);
                    report.Add("RECOVERED new FileOptimizer-specific folder: " + folder + " -> " + destination);
                } catch (Exception e) { report.Add("REVIEW could not preserve/move " + folder + " : " + e.Message); }
            }
        }
    }
    private static void Compare(Dictionary<string,string> oldMap, Dictionary<string,string> newMap, List<string> log, string category)
    {
        foreach (KeyValuePair<string,string> x in newMap) {
            string previous;
            if (!oldMap.TryGetValue(x.Key, out previous)) log.Add(category + " CREATED " + x.Key);
            else if (previous != x.Value) log.Add(category + " CHANGED " + x.Key);
        }
        foreach (KeyValuePair<string,string> x in oldMap)
            if (!newMap.ContainsKey(x.Key)) log.Add(category + " MISSING " + x.Key);
    }
    public void Finish()
    {
        if (finished) return;
        finished = true;
        try {
            after = SnapshotFileSystem();
            regAfter = SnapshotRegistry();
            Compare(before, after, report, "FILESYSTEM");
            Compare(regBefore, regAfter, report, "REGISTRY");
            RecoverNamedNewDirectories();
        } catch (Exception e) { report.Add("AUDIT WARNING " + e); }
        try { RestorePreviousRegistrySession(backupFile, report); }
        catch (Exception e) { report.Add("REGISTRY RESTORE WARNING " + e.Message + "; recovery marker retained"); }
        report.Add("END " + DateTime.UtcNow.ToString("o"));
        string logs = Path.Combine(data,"Logs");
        Directory.CreateDirectory(logs);
        string filename = Path.Combine(logs,"TraceGuard-" + sessionId + ".txt");
        File.WriteAllLines(filename, report.ToArray(), Encoding.UTF8);
        File.WriteAllText(Path.Combine(traceRoot,"LatestReport.txt"), filename, Encoding.UTF8);
    }
}
