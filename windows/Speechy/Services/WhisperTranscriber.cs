using System.Diagnostics;
using System.Text.RegularExpressions;
using Speechy.Models;

namespace Speechy.Services;

/// <summary>
/// Runs whisper-cli.exe as a subprocess to transcribe audio files.
/// Filters out non-speech patterns (music, silence markers) matching the macOS app.
/// </summary>
public class WhisperTranscriber
{
    private WhisperModel _currentModel;

    /// <summary>
    /// Non-speech patterns to filter out, matching the macOS nonSpeechPatterns list.
    /// </summary>
    private static readonly string[] NonSpeechPatterns = new[]
    {
        "[BLANK_AUDIO]",
        "[MUSIC]",
        "[MÜZİK]",
        "(Müzik)",
        "(müzik)",
        "(Music)",
        "(music)",
        "[Müzik]",
        "[müzik]",
        "[Music]",
        "[music]",
        "(Gerilim müziği)",
        "(Hareketli müzik)",
        "[MÜZİK ÇALIYOR]",
        "[...müzik çalıyor...]",
        "(...müzik çalıyor...)",
        "[Sessizlik]",
        "(Sessizlik)",
        "[SILENCE]",
        "(silence)",
        "[Alkış]",
        "(Alkış)",
        "[APPLAUSE]",
        "\u266A",  // ♪
        "\U0001F3B5",  // 🎵
    };

    /// <summary>
    /// Regex patterns for bracketed/parenthesized non-speech descriptions.
    /// </summary>
    private static readonly Regex BracketPattern = new(
        @"\[(?:[^\]]*(?:müzik|music|audio|blank|silence|alkış|applause)[^\]]*)\]",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex ParenPattern = new(
        @"\((?:[^\)]*(?:müzik|music|audio|blank|silence|alkış|applause)[^\)]*)\)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public WhisperTranscriber()
    {
        _currentModel = SettingsManager.Instance.SelectedModel;
    }

    /// <summary>
    /// Updates the model to match current settings.
    /// </summary>
    public void UpdateModel()
    {
        _currentModel = SettingsManager.Instance.SelectedModel;
        Log.Info($"Model changed to: {_currentModel.DisplayName()}");
    }

    /// <summary>
    /// Gets the path to whisper-cli.exe, looking in common locations.
    /// </summary>
    private string GetWhisperPath()
    {
        // Check next to the app executable first
        var appDir = AppDomain.CurrentDomain.BaseDirectory;
        var localPath = Path.Combine(appDir, "whisper-cli.exe");
        if (File.Exists(localPath)) return localPath;

        // Check in PATH
        var pathDirs = Environment.GetEnvironmentVariable("PATH")?.Split(';') ?? Array.Empty<string>();
        foreach (var dir in pathDirs)
        {
            var fullPath = Path.Combine(dir.Trim(), "whisper-cli.exe");
            if (File.Exists(fullPath)) return fullPath;
        }

        // Check common install locations
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var commonPaths = new[]
        {
            Path.Combine(programFiles, "whisper.cpp", "whisper-cli.exe"),
            Path.Combine(programFiles, "whisper", "whisper-cli.exe"),
            Path.Combine(appDir, "whisper", "whisper-cli.exe"),
        };

        foreach (var path in commonPaths)
        {
            if (File.Exists(path)) return path;
        }

        return "whisper-cli.exe"; // Fall back to relying on PATH
    }

    /// <summary>
    /// Filters non-speech content from transcription output.
    /// Returns null if the result is empty or too short after filtering.
    /// </summary>
    public string? FilterNonSpeech(string text)
    {
        var filtered = text;

        // Remove literal non-speech patterns
        foreach (var pattern in NonSpeechPatterns)
        {
            filtered = filtered.Replace(pattern, "");
        }

        // Remove bracketed/parenthesized non-speech descriptions
        filtered = BracketPattern.Replace(filtered, "");
        filtered = ParenPattern.Replace(filtered, "");

        // Clean up whitespace
        filtered = filtered.Trim();
        filtered = Regex.Replace(filtered, @"\s{2,}", " ");

        // If the result is too short or empty, return null
        if (string.IsNullOrWhiteSpace(filtered) || filtered.Length < 2)
        {
            return null;
        }

        return filtered;
    }

    /// <summary>
    /// Transcribes an audio file using whisper-cli.exe.
    /// Returns the transcribed text, or null if transcription failed or produced only non-speech.
    /// </summary>
    public async Task<string?> Transcribe(string audioFilePath, string language)
    {
        var modelToUse = _currentModel;
        var modelDownloadManager = ModelDownloadManager.Instance;

        return await Task.Run(() =>
        {
            try
            {
                var fileInfo = new FileInfo(audioFilePath);
                Log.Info($"Whisper - lang: {language}, model: {modelToUse.RawValue()}, audio size: {fileInfo.Length} bytes");

                var modelPath = modelDownloadManager.GetModelPath(modelToUse);
                if (!modelDownloadManager.ModelExists(modelToUse))
                {
                    Log.Error($"Model not found at {modelPath}");
                    return null;
                }

                var whisperPath = GetWhisperPath();
                Log.Info($"Using whisper at: {whisperPath}");

                var langArg = language == "auto" ? "auto" : language;
                var arguments = $"-m \"{modelPath}\" -l {langArg} -nt -np \"{audioFilePath}\"";

                var startInfo = new ProcessStartInfo
                {
                    FileName = whisperPath,
                    Arguments = arguments,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8,
                    StandardErrorEncoding = System.Text.Encoding.UTF8
                };

                using var process = new Process { StartInfo = startInfo };
                var outputBuilder = new System.Text.StringBuilder();
                var errorBuilder = new System.Text.StringBuilder();

                process.OutputDataReceived += (_, e) =>
                {
                    if (e.Data != null) outputBuilder.AppendLine(e.Data);
                };
                process.ErrorDataReceived += (_, e) =>
                {
                    if (e.Data != null) errorBuilder.AppendLine(e.Data);
                };

                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                // Wait up to 120 seconds for transcription
                if (!process.WaitForExit(120_000))
                {
                    Log.Error("Whisper process timed out after 120 seconds");
                    try { process.Kill(); } catch { }
                    return null;
                }

                var output = outputBuilder.ToString().Trim();
                var errors = errorBuilder.ToString().Trim();

                if (process.ExitCode != 0)
                {
                    Log.Error($"Whisper exited with code {process.ExitCode}: {errors}");
                    return null;
                }

                if (string.IsNullOrWhiteSpace(output))
                {
                    Log.Info("Whisper produced no output");
                    return null;
                }

                Log.Info($"Whisper raw output: {output}");

                // Filter non-speech content
                var filteredText = FilterNonSpeech(output);
                if (filteredText == null)
                {
                    Log.Info("Whisper output was all non-speech content");
                    return null;
                }

                Log.Info($"Whisper result: {filteredText}");
                return filteredText;
            }
            catch (Exception ex)
            {
                Log.Error("Whisper transcription failed", ex);
                return null;
            }
        });
    }
}
