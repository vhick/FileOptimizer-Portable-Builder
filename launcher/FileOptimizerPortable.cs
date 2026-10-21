// Community portable launcher for FileOptimizer. Original app binary and bundled plugins are unchanged.
// Windows/.NET Framework 4.8 only. No install, system-wide environment changes, registry cleanup or automation.
using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class FileOptimizerPortable
{
    static readonly string[] ManagedNames = { "FileOptimizer.ini", "FileOptimizer64.ini", "FileOptimizer32.ini",
        "FileOptimizer.log", "FileOptimizer64.log", "FileOptimizer32.log" };
    static bool IsLog(string name) { return name.EndsWith(".log", StringComparison.OrdinalIgnoreCase); }
    static void Alert(string message) { MessageBox.Show(message, "FileOptimizer Portable", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    static string Root { get { return AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar); } }
    static string App { get { return Path.Combine(Root, "App", "FileOptimizer"); } }
    static string Data { get { return Path.Combine(Root, "Data"); } }
    static string Storage(string name) { return Path.Combine(Data, IsLog(name) ? "Logs" : "Settings", name); }

    static void AtomicCopy(string src, string dst)
    {
        // Copy to a temporary file in the destination folder first, keeping existing Data files intact on failure.
        Directory.CreateDirectory(Path.GetDirectoryName(dst));
        string temp = dst + ".new-" + Guid.NewGuid().ToString("N");
        try
        {
            File.Copy(src, temp, true);
            if (File.Exists(dst))
            {
                // Back up persistent Data before replacing; do not clutter replaceable App/.
                string backup = dst.StartsWith(Data + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                    ? dst + ".previous" : null;
                File.Replace(temp, dst, backup, true);
            }
            else File.Move(temp, dst);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    static void CopyAppToData()
    {
        foreach (string name in ManagedNames)
        {
            string src = Path.Combine(App, name);
            if (File.Exists(src)) AtomicCopy(src, Storage(name));
        }
    }
    static void CopyDataToApp()
    {
        foreach (string name in ManagedNames)
        {
            string src = Storage(name);
            if (File.Exists(src)) AtomicCopy(src, Path.Combine(App, name));
        }
    }
    static string LockId()
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] b = sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(Root).ToUpperInvariant()));
            return BitConverter.ToString(b, 0, 12).Replace("-", "");
        }
    }
    static void RequireWritable(string folder)
    {
        Directory.CreateDirectory(folder);
        string p = Path.Combine(folder, ".portable-write-test-" + Guid.NewGuid().ToString("N"));
        try { File.WriteAllText(p, "test"); }
        finally { if (File.Exists(p)) File.Delete(p); }
    }
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            bool good = File.Exists(Path.Combine(App, "FileOptimizer64.exe")) &&
                Directory.Exists(Path.Combine(App, "Plugins64")) && Directory.Exists(Data) &&
                File.Exists(Path.Combine(Root, "App", "AppInfo", "appinfo.ini"));
            return good ? 0 : 4;
        }
        // Startup arguments are passed through; operations only occur when explicitly requested by the user.
        Mutex gate = null;
        try
        {
            bool owned;
            gate = new Mutex(true, @"Local\FileOptimizerPortable_" + LockId(), out owned);
            if (!owned) { Alert("This portable copy is already running. Close it before starting another session."); return 2; }
            string exe = Path.Combine(App, "FileOptimizer64.exe");
            if (!File.Exists(exe)) throw new FileNotFoundException("Official 64-bit FileOptimizer binary is missing.", exe);
            RequireWritable(App);
            RequireWritable(Data);
            Directory.CreateDirectory(Path.Combine(Data, "Settings"));
            Directory.CreateDirectory(Path.Combine(Data, "Logs"));
            string tempDir = Path.Combine(Data, "Temp");
            RequireWritable(tempDir);
            // Recover settings if a prior launcher was interrupted: staged App files are newer than Data files.
            // Never overwrite Data with an older App copy.
            foreach (string name in ManagedNames)
            {
                string appFile = Path.Combine(App, name), dataFile = Storage(name);
                if (File.Exists(appFile) && (!File.Exists(dataFile) ||
                    File.GetLastWriteTimeUtc(appFile) > File.GetLastWriteTimeUtc(dataFile)))
                    AtomicCopy(appFile, dataFile);
            }
            CopyDataToApp();
            int exitCode;
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe);
                psi.UseShellExecute = false;
                psi.WorkingDirectory = App; // required for relative Plugins64 paths
                psi.EnvironmentVariables["TEMP"] = tempDir;
                psi.EnvironmentVariables["TMP"] = tempDir;
                psi.Arguments = QuoteArgs(args);
                using (Process p = Process.Start(psi))
                {
                    if (p == null) throw new Exception("Could not start FileOptimizer.");
                    p.WaitForExit();
                    exitCode = p.ExitCode;
                }
            }
            finally { CopyAppToData(); } // Capture preferences/logs even on unexpected child failure.
            return exitCode;
        }
        catch (Exception ex) { Alert(ex.Message + "\n\nSettings in Data/ were not intentionally deleted."); return 1; }
        finally { if (gate != null) { try { gate.ReleaseMutex(); } catch (ApplicationException) {} gate.Dispose(); } }
    }
    static string QuoteArgs(string[] args)
    {
        // Windows CommandLineToArgvW-compatible quoting; no shell is involved.
        List<string> quoted = new List<string>();
        foreach (string s in args)
        {
            StringBuilder b = new StringBuilder("\""); int backslashes = 0;
            foreach (char c in s)
            {
                if (c == '\\') { backslashes++; continue; }
                if (c == '"') { b.Append('\\', backslashes * 2 + 1); b.Append('"'); backslashes = 0; continue; }
                b.Append('\\', backslashes); backslashes = 0; b.Append(c);
            }
            b.Append('\\', backslashes * 2); b.Append('"'); quoted.Add(b.ToString());
        }
        return String.Join(" ", quoted.ToArray());
    }
}
