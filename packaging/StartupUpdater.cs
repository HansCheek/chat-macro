using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class UpdateConfig
{
    public string repository { get; set; }
    public string publicKey { get; set; }
}

internal sealed class UpdateManifest
{
    public int format { get; set; }
    public string repository { get; set; }
    public string version { get; set; }
    public string asset { get; set; }
    public string sha256 { get; set; }
    public string signature { get; set; }
}

internal static class StartupUpdater
{
    internal static readonly string CacheRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChatMacro", "Updates");
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    internal static string ResolveWithWindow()
    {
        string result = null;
        using (Form splash = new Form())
        using (BackgroundWorker worker = new BackgroundWorker())
        {
            splash.Text = "채팅 매크로";
            splash.ClientSize = new Size(360, 126);
            splash.StartPosition = FormStartPosition.CenterScreen;
            splash.FormBorderStyle = FormBorderStyle.FixedDialog;
            splash.ControlBox = false;
            splash.BackColor = Color.FromArgb(246, 241, 252);
            using (Icon icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath)) splash.Icon = (Icon)icon.Clone();
            Label label = new Label { Text = "최신 버전 확인 중...", Location = new Point(24, 23),
                Size = new Size(312, 48), Font = new Font("맑은 고딕", 11), ForeColor = Color.FromArgb(88, 57, 120) };
            ProgressBar bar = new ProgressBar { Location = new Point(24, 86), Size = new Size(312, 12), Style = ProgressBarStyle.Marquee };
            splash.Controls.Add(label);
            splash.Controls.Add(bar);
            Action<string> report = delegate(string text) {
                if (!splash.IsDisposed && splash.IsHandleCreated)
                    splash.BeginInvoke((Action)delegate { label.Text = text; });
            };
            worker.DoWork += delegate(object sender, DoWorkEventArgs e) { e.Result = Resolve(ReadConfig(),
                Assembly.GetExecutingAssembly().GetName().Version, report); };
            worker.RunWorkerCompleted += delegate(object sender, RunWorkerCompletedEventArgs e) {
                if (e.Error == null) result = e.Result as string;
                splash.Close();
            };
            splash.Shown += delegate { worker.RunWorkerAsync(); };
            Application.Run(splash);
        }
        return result;
    }

    internal static UpdateConfig ReadConfig()
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("update-config.json"))
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
            return Json.Deserialize<UpdateConfig>(reader.ReadToEnd());
    }

    internal static string Resolve(UpdateConfig config, Version current, Action<string> report)
    {
        return Resolve(config, current, report, CacheRoot, Download);
    }

    internal static string Resolve(UpdateConfig config, Version current, Action<string> report, string cacheRoot, Func<string, int, int, byte[]> download)
    {
        string candidate = null;
        Version candidateVersion = current;
        string index = Path.Combine(cacheRoot, "current.json");
        try
        {
            if (File.Exists(index))
            {
                UpdateManifest cached = Json.Deserialize<UpdateManifest>(File.ReadAllText(index, Encoding.UTF8));
                Version version;
                if (VerifyManifest(config, cached, out version) && version > current)
                {
                    string path = GetCachePath(cached.version, cacheRoot);
                    if (VerifyFile(path, cached.sha256)) { candidate = path; candidateVersion = version; }
                }
            }
        }
        catch (Exception e) { Log(e); }

        try
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            string manifestUrl = "https://github.com/" + config.repository + "/releases/latest/download/update.json";
            UpdateManifest remote = Json.Deserialize<UpdateManifest>(Encoding.UTF8.GetString(download(manifestUrl, 65536, 4500)));
            Version version;
            if (!VerifyManifest(config, remote, out version)) throw new InvalidDataException("Invalid update signature.");
            if (version <= candidateVersion) return candidate;
            report("새 버전 " + remote.version + " 다운로드 중...");
            string destination = GetCachePath(remote.version, cacheRoot);
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            if (!VerifyFile(destination, remote.sha256))
            {
                string url = "https://github.com/" + config.repository + "/releases/download/v" + remote.version + "/ChatMacro.exe";
                byte[] bytes = download(url, 67108864, 20000);
                if (!String.Equals(Hash(bytes), remote.sha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Update checksum mismatch.");
                string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try
                {
                    File.WriteAllBytes(temporary, bytes);
                    if (File.Exists(destination)) File.Delete(destination);
                    File.Move(temporary, destination);
                }
                finally { if (File.Exists(temporary)) File.Delete(temporary); }
            }
            string pendingIndex = index + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(pendingIndex, Json.Serialize(remote), new UTF8Encoding(false));
                if (File.Exists(index)) File.Replace(pendingIndex, index, null);
                else File.Move(pendingIndex, index);
            }
            finally { if (File.Exists(pendingIndex)) File.Delete(pendingIndex); }
            return destination;
        }
        catch (Exception e) { Log(e); return candidate; }
    }

    internal static string GetCachePath(string version)
    {
        return GetCachePath(version, CacheRoot);
    }

    internal static string GetCachePath(string version, string cacheRoot)
    {
        if (!Regex.IsMatch(version ?? "", @"^\d{1,5}\.\d{1,5}\.\d{1,5}$")) throw new InvalidDataException("Invalid version.");
        return Path.Combine(cacheRoot, version, "ChatMacro.exe");
    }

    internal static byte[] Canonical(UpdateManifest manifest)
    {
        return Encoding.UTF8.GetBytes("ChatMacro-Update-v1\n" + manifest.repository + "\n" + manifest.version + "\n" +
            manifest.asset + "\n" + manifest.sha256.ToUpperInvariant() + "\n");
    }

    internal static bool VerifyManifest(UpdateConfig config, UpdateManifest manifest, out Version version)
    {
        version = null;
        try
        {
            if (manifest == null || manifest.format != 1 || manifest.repository != config.repository || manifest.asset != "ChatMacro.exe" ||
                !Regex.IsMatch(manifest.version ?? "", @"^\d{1,5}\.\d{1,5}\.\d{1,5}$") ||
                !Version.TryParse(manifest.version, out version) || !Regex.IsMatch(manifest.sha256 ?? "", "^[a-fA-F0-9]{64}$")) return false;
            using (RSACryptoServiceProvider rsa = new RSACryptoServiceProvider())
            {
                rsa.PersistKeyInCsp = false;
                rsa.FromXmlString(config.publicKey);
                return rsa.VerifyData(Canonical(manifest), CryptoConfig.MapNameToOID("SHA256"), Convert.FromBase64String(manifest.signature));
            }
        }
        catch { return false; }
    }

    internal static string Hash(byte[] bytes)
    {
        using (SHA256 sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
    }

    internal static bool VerifyFile(string path, string expected)
    {
        if (!File.Exists(path)) return false;
        using (FileStream stream = File.OpenRead(path))
        using (SHA256 sha = SHA256.Create())
            return String.Equals(BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", ""), expected, StringComparison.OrdinalIgnoreCase);
    }

    private static byte[] Download(string url, int maxBytes, int timeout)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.UserAgent = "ChatMacro-AutoUpdate/1.1";
        request.Timeout = timeout;
        request.ReadWriteTimeout = timeout;
        request.MaximumAutomaticRedirections = 5;
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        {
            string host = response.ResponseUri.Host;
            if (response.ResponseUri.Scheme != "https" || !(host == "github.com" || host == "release-assets.githubusercontent.com" ||
                host == "objects.githubusercontent.com" || host == "github-releases.githubusercontent.com")) throw new InvalidDataException("Unexpected update host.");
            if (response.ContentLength > maxBytes) throw new InvalidDataException("Update too large.");
            using (Stream stream = response.GetResponseStream())
            using (MemoryStream output = new MemoryStream())
            {
                byte[] buffer = new byte[32768];
                int read;
                Stopwatch total = Stopwatch.StartNew();
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    if (output.Length + read > maxBytes || total.ElapsedMilliseconds > timeout) throw new InvalidDataException("Update transfer limit exceeded.");
                    output.Write(buffer, 0, read);
                }
                return output.ToArray();
            }
        }
    }

    private static void Log(Exception error)
    {
        try
        {
            Directory.CreateDirectory(CacheRoot);
            File.WriteAllText(Path.Combine(CacheRoot, "last-check.txt"), DateTime.UtcNow.ToString("O") + " " + error.GetType().Name);
        }
        catch { }
    }
}
