namespace Speechy.Services;

/// <summary>
/// Singleton logger that writes timestamped messages to %APPDATA%/Speechy/speechy_debug.log.
/// Matches the macOS [HH:mm:ss] [Speechy] message format.
/// Also maintains an in-memory buffer (last 200 lines) and fires LogEntryAdded
/// so the Logs UI tab can display entries live.
/// </summary>
public sealed class Logger
{
    private static readonly Lazy<Logger> _instance = new(() => new Logger());
    public static Logger Instance => _instance.Value;

    /// <summary>Fired on the calling thread whenever a new log line is appended.</summary>
    public event Action<string>? LogEntryAdded;

    private readonly List<string> _buffer = new();
    private const int MaxBufferLines = 200;

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
    /// Also appends to the in-memory buffer and fires LogEntryAdded.
    /// </summary>
    public void Log(string message)
    {
        try
        {
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            var line = $"[{timestamp}] [Speechy] {message}";

            lock (_lock)
            {
                File.AppendAllText(_logFilePath, line + Environment.NewLine);
                _buffer.Add(line);
                if (_buffer.Count > MaxBufferLines)
                    _buffer.RemoveAt(0);
            }

            LogEntryAdded?.Invoke(line);
        }
        catch
        {
            // Silently fail - logging should never crash the app
        }
    }

    /// <summary>
    /// Returns a snapshot of the in-memory log buffer (up to last 200 lines).
    /// </summary>
    public IReadOnlyList<string> GetBuffer()
    {
        lock (_lock)
        {
            return _buffer.ToList();
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
    /// Clears the log file and the in-memory buffer.
    /// </summary>
    public void Clear()
    {
        try
        {
            lock (_lock)
            {
                File.WriteAllText(_logFilePath, string.Empty);
                _buffer.Clear();
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
