using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Threading;

internal static class MacroRuntime
{
    internal static int Run(string directory)
    {
        // The UI belongs to ChatMacro.exe, so the taskbar pins this executable.
        // Windows PowerShell's engine is hosted as a library, never as a child app.
        Environment.SetEnvironmentVariable("CHATMACRO_VERSION", Assembly.GetExecutingAssembly().GetName().Version.ToString(3));
        string source = File.ReadAllText(Path.Combine(directory, "macro.ps1"));
        source = source.Replace("$PSScriptRoot", "$AppResourceRoot");
        using (Runspace runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault()))
        {
            runspace.ApartmentState = ApartmentState.STA;
            runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
            runspace.Open();
            runspace.SessionStateProxy.SetVariable("AppResourceRoot", directory);
            using (PowerShell shell = PowerShell.Create())
            {
                shell.Runspace = runspace;
                shell.AddScript(source);
                shell.Invoke();
                if (shell.HadErrors) throw new InvalidOperationException(shell.Streams.Error[0].ToString());
            }
        }
        return 0;
    }
}
