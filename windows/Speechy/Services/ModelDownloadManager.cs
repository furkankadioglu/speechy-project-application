using System.ComponentModel;
using System.Net.Http;
using System.Runtime.CompilerServices;
using Speechy.Models;

namespace Speechy.Services;

/// <summary>
/// Manages downloading, checking, and deleting Whisper model files.
/// Models are stored in %APPDATA%/Speechy/Models/.
/// </summary>
public sealed class ModelDownloadManager : INotifyPropertyChanged
{
    private static readonly Lazy<ModelDownloadManager> _instance = new(() => new ModelDownloadManager());
    public static ModelDownloadManager Instance => _instance.Value;

    public event PropertyChangedEventHandler? PropertyChanged;

    private readonly string _modelsDir;
    private readonly HttpClient _httpClient;

    private bool _isDownloading;
    private double _downloadProgress;
    private string _downloadStatus = "";
    private WhisperModel? _currentlyDownloading;
    private CancellationTokenSource? _downloadCts;

    private ModelDownloadManager()
    {
        _modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Speechy", "Models");
        Directory.CreateDirectory(_modelsDir);

        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Speechy/1.0");
    }

    public bool IsDownloading
    {
        get => _isDownloading;
        private set { _isDownloading = value; OnPropertyChanged(); }
    }

    public double DownloadProgress
    {
        get => _downloadProgress;
        private set { _downloadProgress = value; OnPropertyChanged(); }
    }

    public string DownloadStatus
    {
        get => _downloadStatus;
        private set { _downloadStatus = value; OnPropertyChanged(); }
    }

    public WhisperModel? CurrentlyDownloading
    {
        get => _currentlyDownloading;
        private set { _currentlyDownloading = value; OnPropertyChanged(); }
    }

    /// <summary>
    /// Gets the full path where a model file would be stored.
    /// </summary>
    public string GetModelPath(WhisperModel model)
    {
        return Path.Combine(_modelsDir, model.FileName());
    }

    /// <summary>
    /// Checks if a model file exists on disk.
    /// </summary>
    public bool ModelExists(WhisperModel model)
    {
        var path = GetModelPath(model);
        return File.Exists(path);
    }

    /// <summary>
    /// Deletes a downloaded model file.
    /// </summary>
    public bool DeleteModel(WhisperModel model)
    {
        try
        {
            var path = GetModelPath(model);
            if (File.Exists(path))
            {
                File.Delete(path);
                Log.Info($"Deleted model: {model.DisplayName()} at {path}");
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Log.Error($"Failed to delete model {model.DisplayName()}", ex);
            return false;
        }
    }

    /// <summary>
    /// Gets the actual file size of a downloaded model.
    /// </summary>
    public long GetModelFileSize(WhisperModel model)
    {
        var path = GetModelPath(model);
        if (!File.Exists(path)) return 0;
        return new FileInfo(path).Length;
    }

    /// <summary>
    /// Cancels the current download.
    /// </summary>
    public void CancelDownload()
    {
        _downloadCts?.Cancel();
        Log.Info("Model download cancelled");
    }

    /// <summary>
    /// Downloads a Whisper model from HuggingFace with progress reporting.
    /// </summary>
    /// <param name="model">The model to download.</param>
    /// <param name="progress">Optional IProgress for reporting download progress (0.0 - 1.0).</param>
    /// <returns>True if download completed successfully.</returns>
    public async Task<bool> DownloadModel(WhisperModel model, IProgress<double>? progress = null)
    {
        if (IsDownloading)
        {
            Log.Info("Download already in progress");
            return false;
        }

        if (ModelExists(model))
        {
            Log.Info($"Model {model.DisplayName()} already exists");
            return true;
        }

        IsDownloading = true;
        CurrentlyDownloading = model;
        DownloadProgress = 0;
        DownloadStatus = $"Downloading {model.DisplayName()}...";
        _downloadCts = new CancellationTokenSource();

        var destPath = GetModelPath(model);
        var tempPath = destPath + ".download";

        try
        {
            Log.Info($"Starting download: {model.DisplayName()} from {model.DownloadUrl()}");

            using var response = await _httpClient.GetAsync(model.DownloadUrl(), HttpCompletionOption.ResponseHeadersRead, _downloadCts.Token);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? model.FileSize();
            var bytesRead = 0L;

            await using var contentStream = await response.Content.ReadAsStreamAsync(_downloadCts.Token);
            await using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

            var buffer = new byte[81920];
            int read;
            var lastProgressReport = DateTime.UtcNow;

            while ((read = await contentStream.ReadAsync(buffer, _downloadCts.Token)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read), _downloadCts.Token);
                bytesRead += read;

                // Throttle progress updates to ~10 per second
                var now = DateTime.UtcNow;
                if ((now - lastProgressReport).TotalMilliseconds >= 100)
                {
                    var progressValue = (double)bytesRead / totalBytes;
                    DownloadProgress = progressValue;
                    progress?.Report(progressValue);

                    var mbDownloaded = bytesRead / 1_048_576.0;
                    var mbTotal = totalBytes / 1_048_576.0;
                    DownloadStatus = $"Downloading {model.DisplayName()} - {mbDownloaded:F1} / {mbTotal:F0} MB";

                    lastProgressReport = now;
                }
            }

            // Move temp file to final location
            if (File.Exists(destPath))
                File.Delete(destPath);
            File.Move(tempPath, destPath);

            DownloadProgress = 1.0;
            DownloadStatus = $"{model.DisplayName()} downloaded successfully";
            Log.Info($"Model download complete: {model.DisplayName()} ({bytesRead:N0} bytes)");
            return true;
        }
        catch (OperationCanceledException)
        {
            DownloadStatus = "Download cancelled";
            Log.Info($"Model download cancelled: {model.DisplayName()}");
            CleanupTempFile(tempPath);
            return false;
        }
        catch (Exception ex)
        {
            DownloadStatus = $"Download failed: {ex.Message}";
            Log.Error($"Model download failed: {model.DisplayName()}", ex);
            CleanupTempFile(tempPath);
            return false;
        }
        finally
        {
            IsDownloading = false;
            CurrentlyDownloading = null;
            _downloadCts?.Dispose();
            _downloadCts = null;
        }
    }

    private void CleanupTempFile(string tempPath)
    {
        try
        {
            if (File.Exists(tempPath))
                File.Delete(tempPath);
        }
        catch { }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
