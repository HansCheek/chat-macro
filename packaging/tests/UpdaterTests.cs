using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

internal static class UpdaterTests
{
    private static int checks;
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
        checks++;
    }
    private static UpdateManifest Sign(UpdateConfig config, RSACryptoServiceProvider rsa, string version, byte[] payload)
    {
        UpdateManifest manifest = new UpdateManifest { format = 1, repository = config.repository, version = version,
            asset = "ChatMacro.exe", sha256 = StartupUpdater.Hash(payload) };
        manifest.signature = Convert.ToBase64String(rsa.SignData(StartupUpdater.Canonical(manifest), CryptoConfig.MapNameToOID("SHA256")));
        return manifest;
    }
    private static byte[] Encode(UpdateManifest manifest) { return Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(manifest)); }
    [STAThread]
    private static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "ChatMacro updater tests " + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        using (RSACryptoServiceProvider rsa = new RSACryptoServiceProvider(2048))
        {
            rsa.PersistKeyInCsp = false;
            UpdateConfig config = new UpdateConfig { repository = "test-owner/chat-macro", publicKey = rsa.ToXmlString(false) };
            byte[] payload = Encoding.UTF8.GetBytes("signed test fixture, never executed");
            UpdateManifest manifest = Sign(config, rsa, "1.2.0", payload);
            Version parsed;
            Assert(StartupUpdater.VerifyManifest(config, manifest, out parsed), "Valid signature rejected");
            string signature = manifest.signature;
            manifest.signature = Convert.ToBase64String(new byte[256]);
            Assert(!StartupUpdater.VerifyManifest(config, manifest, out parsed), "Invalid signature accepted");
            manifest.signature = signature;
            manifest.repository = "other-owner/chat-macro";
            Assert(!StartupUpdater.VerifyManifest(config, manifest, out parsed), "Wrong repository accepted");
            manifest.repository = config.repository;
            manifest.version = "../outside";
            Assert(!StartupUpdater.VerifyManifest(config, manifest, out parsed), "Path traversal accepted");
            manifest.version = "1.2.0";
            manifest.asset = "other.exe";
            Assert(!StartupUpdater.VerifyManifest(config, manifest, out parsed), "Unexpected asset accepted");
            manifest.asset = "ChatMacro.exe";
            int downloads = 0;
            Func<string, int, int, byte[]> network = delegate(string url, int max, int timeout) {
                Assert(url.StartsWith("https://github.com/test-owner/chat-macro/"), "Unexpected repository URL");
                downloads++;
                if (url.EndsWith("update.json")) return Encode(manifest);
                Assert(url.EndsWith("/releases/download/v1.2.0/ChatMacro.exe"), "Unexpected asset URL");
                return payload;
            };
            string result = StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, root, network);
            Assert(result == Path.Combine(root, "1.2.0", "ChatMacro.exe"), "New update not selected");
            Assert(downloads == 2 && StartupUpdater.VerifyFile(result, manifest.sha256), "Download hash failed");
            Func<string, int, int, byte[]> offline = delegate { throw new IOException("Offline fixture"); };
            Assert(StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, root, offline) == result, "Offline cache unavailable");
            UpdateManifest older = Sign(config, rsa, "1.1.0", payload);
            Assert(StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, root, delegate { return Encode(older); }) == result, "Downgrade allowed");
            manifest = Sign(config, rsa, "1.3.0", payload);
            string corrupt = StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, root,
                delegate(string url, int max, int timeout) { return url.EndsWith("update.json") ? Encode(manifest) : Encoding.UTF8.GetBytes("corrupt"); });
            Assert(corrupt == result && !File.Exists(Path.Combine(root, "1.3.0", "ChatMacro.exe")), "Corrupt payload accepted");
            File.WriteAllText(result, "locally tampered");
            Assert(StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, root, offline) == null, "Tampered local cache accepted");
            string clean = Path.Combine(root, "clean");
            Assert(StartupUpdater.Resolve(config, new Version("1.1.0"), delegate { }, clean, offline) == null, "Offline clean startup failed");
            manifest = Sign(config, rsa, "1.1.0", payload);
            int calls = 0;
            Assert(StartupUpdater.Resolve(config, new Version("1.1.0.0"), delegate { }, clean,
                delegate { calls++; return Encode(manifest); }) == null && calls == 1, "Same version was downloaded again");
        }
        Console.WriteLine("PASS: " + checks + " updater assertions; no downloaded fixture executed.");
        return 0;
    }
}
