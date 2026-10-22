using System;
using System.Diagnostics;

class RcWrapper {
    static int Main(string[] args) {
        bool hasNoPreprocess = false;
        for (int i = 0; i < args.Length; i++) {
            if (args[i].Equals("-no-preprocess", StringComparison.OrdinalIgnoreCase) ||
                args[i].Equals("/no-preprocess", StringComparison.OrdinalIgnoreCase)) {
                hasNoPreprocess = true;
                break;
            }
        }
        string cmdArgs = hasNoPreprocess ? "" : "-no-preprocess";
        for (int i = 0; i < args.Length; i++) {
            string a = args[i];
            if (a.Contains(" ") || a.Contains("\t")) {
                cmdArgs += " \"" + a.Replace("\"", "\\\"") + "\"";
            } else {
                cmdArgs += " " + a;
            }
        }
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = @"C:\projects\andirun\platform-tools\llvm-rc.exe";
        psi.Arguments = cmdArgs.TrimStart();
        psi.UseShellExecute = false;
        Process p = Process.Start(psi);
        if (p == null) return 1;
        p.WaitForExit();
        return p.ExitCode;
    }
}
