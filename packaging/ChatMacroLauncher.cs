using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("채팅 매크로")]
[assembly: AssemblyDescription("선택한 클라이언트에 채팅을 자동 입력하는 반복 매크로")]
[assembly: AssemblyProduct("Chat Macro")]

internal static class ChatMacroLauncher
{
    private static readonly string[] Files = { "macro.ps1", "assets/chat-macro.png", "assets/chat-macro.ico" };

    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        if (Array.IndexOf(args, "--updated-start") < 0)
        {
            string updated = StartupUpdater.ResolveWithWindow();
            if (!String.IsNullOrEmpty(updated))
            {
                using (Process process = Process.Start(new ProcessStartInfo(updated, "--updated-start")
                { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden }))
                {
                    if (process == null) return 1;
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
        }
        string session = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ChatMacro", "Sessions", Guid.NewGuid().ToString("N"));
        try
        {
            ExtractResources(session);
            using (Process process = Process.Start(CreateStartInfo(session)))
            {
                if (process == null) throw new InvalidOperationException("매크로를 실행하지 못했습니다.");
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "채팅 매크로 실행 오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { Cleanup(session); }
    }

    internal static void ExtractResources(string directory)
    {
        foreach (string file in Files)
        {
            string destination = Path.Combine(directory, file.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(file))
            {
                if (source == null) throw new InvalidOperationException("필수 파일이 없습니다: " + file);
                using (FileStream output = File.Create(destination)) source.CopyTo(output);
            }
        }
    }

    internal static ProcessStartInfo CreateStartInfo(string directory)
    {
        ProcessStartInfo info = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(directory, "macro.ps1") + "\"",
            WorkingDirectory = directory,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        info.EnvironmentVariables["CHATMACRO_VERSION"] = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
        return info;
    }

    private static void Cleanup(string directory)
    {
        // Only remove the exact files created for this unique launch; never recurse.
        try
        {
            foreach (string file in Files) File.Delete(Path.Combine(directory, file.Replace('/', Path.DirectorySeparatorChar)));
            string assets = Path.Combine(directory, "assets");
            if (Directory.Exists(assets)) Directory.Delete(assets, false);
            if (Directory.Exists(directory)) Directory.Delete(directory, false);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
