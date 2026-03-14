namespace Speechy.Services;

/// <summary>
/// Singleton logger that writes timestamped messages to %APPDATA%/Speechy/speechy_debug.log.
/// Matches the macOS [HH:mm:ss] [Speechy] message format.
/// </summary>
public sealed class Logger
{
    private static readonly Lazy<Logger> _instance = new(() => new Logger());
    public static Logger Instance => _instance.Value;

    private readonly string _logFilePath;
    private readonly object _lock = new();

    private Logger()
    {
        var appDataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Speechy");

        Directory.CreateDirectory(appDataDir);
        _logFilePath = Path.Combine(appDataDir, "speechy_debug.log");
    }

    /// <summary>
    /// Logs a message with timestamp in the format [HH:mm:ss] [Speechy] message.
    /// </summary>
    public void Log(string message)
    {
        try
        {
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            var line = $"[{timestamp}] [Speechy] {message}{Environment.NewLine}";

            lock (_lock)
            {
                File.AppendAllText(_logFilePath, line);
            }
        }
        catch
        {
            // Silently fail - logging should never crash the app
        }
    }

    /// <summary>
    /// Logs an error message with exception details.
    /// </summary>
    public void LogError(string message, Exception? ex = null)
    {
        var errorMessage = ex != null
            ? $"ERROR: {message} - {ex.GetType().Name}: {ex.Message}"
            : $"ERROR: {message}";
        Log(errorMessage);
    }

    /// <summary>
    /// Gets the full path to the log file.
    /// </summary>
    public string LogFilePath => _logFilePath;

    /// <summary>
    /// Clears the log file.
    /// </summary>
    public void Clear()
    {
        try
        {
            lock (_lock)
            {
                File.WriteAllText(_logFilePath, string.Empty);
            }
        }
        catch
        {
            // Silently fail
        }
    }
}

/// <summary>
/// Static convenience methods for logging.
/// </summary>
public static class Log
{
    public static void Info(string message) => Logger.Instance.Log(message);
    public static void Error(string message, Exception? ex = null) => Logger.Instance.LogError(message, ex);
}
