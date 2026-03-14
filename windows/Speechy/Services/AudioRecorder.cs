using System.ComponentModel;
using System.Runtime.CompilerServices;
using NAudio.Wave;

namespace Speechy.Services;

/// <summary>
/// Records audio using NAudio, saves to a temporary WAV file,
/// and converts to 16kHz mono 16-bit PCM format for Whisper.
/// Provides real-time audio level for waveform visualization.
/// </summary>
public class AudioRecorder : INotifyPropertyChanged, IDisposable
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action<float>? AudioLevelChanged;

    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _tempFilePath;
    private bool _isRecording;
    private float _currentLevel;
    private readonly object _lock = new();

    public bool IsRecording
    {
        get => _isRecording;
        private set { _isRecording = value; OnPropertyChanged(); }
    }

    public float CurrentLevel
    {
        get => _currentLevel;
        private set { _currentLevel = value; OnPropertyChanged(); }
    }

    /// <summary>
    /// Gets the path to the last recorded (and converted) audio file.
    /// </summary>
    public string? LastRecordingPath { get; private set; }

    /// <summary>
    /// Starts recording audio from the specified device.
    /// </summary>
    /// <param name="deviceId">The device ID to record from, or "system_default" for the default device.</param>
    public void StartRecording(string deviceId = "system_default")
    {
        if (IsRecording) return;

        try
        {
            _tempFilePath = Path.Combine(Path.GetTempPath(), $"speechy_recording_{Guid.NewGuid()}.wav");

            // Find the device number
            int deviceNumber = -1; // default device
            if (deviceId != "system_default")
            {
                for (int i = 0; i < WaveInEvent.DeviceCount; i++)
                {
                    var caps = WaveInEvent.GetCapabilities(i);
                    if (caps.ProductName == deviceId || i.ToString() == deviceId)
                    {
                        deviceNumber = i;
                        break;
                    }
                }
            }

            // Record at 16kHz mono 16-bit PCM directly (Whisper format)
            var waveFormat = new WaveFormat(16000, 16, 1);

            _waveIn = new WaveInEvent
            {
                DeviceNumber = deviceNumber >= 0 ? deviceNumber : 0,
                WaveFormat = waveFormat,
                BufferMilliseconds = 50
            };

            _writer = new WaveFileWriter(_tempFilePath, waveFormat);

            _waveIn.DataAvailable += OnDataAvailable;
            _waveIn.RecordingStopped += OnRecordingStopped;

            _waveIn.StartRecording();
            IsRecording = true;
            Log.Info($"Recording started (device: {(deviceId == "system_default" ? "default" : deviceId)})");
        }
        catch (Exception ex)
        {
            Log.Error("Failed to start recording", ex);
            Cleanup();
        }
    }

    /// <summary>
    /// Stops recording and returns the path to the converted audio file.
    /// </summary>
    /// <returns>Path to the 16kHz mono WAV file, or null if recording failed.</returns>
    public string? StopRecording()
    {
        if (!IsRecording) return null;

        try
        {
            _waveIn?.StopRecording();
            return _tempFilePath;
        }
        catch (Exception ex)
        {
            Log.Error("Failed to stop recording", ex);
            return null;
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_lock)
        {
            try
            {
                _writer?.Write(e.Buffer, 0, e.BytesRecorded);

                // Calculate audio level for visualization
                float maxSample = 0;
                for (int i = 0; i < e.BytesRecorded - 1; i += 2)
                {
                    short sample = (short)(e.Buffer[i] | (e.Buffer[i + 1] << 8));
                    float sampleF = Math.Abs(sample / 32768f);
                    if (sampleF > maxSample) maxSample = sampleF;
                }

                CurrentLevel = maxSample;
                AudioLevelChanged?.Invoke(maxSample);
            }
            catch (Exception ex)
            {
                Log.Error("Error processing audio data", ex);
            }
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        lock (_lock)
        {
            try
            {
                _writer?.Dispose();
                _writer = null;

                if (e.Exception != null)
                {
                    Log.Error("Recording stopped with error", e.Exception);
                }
                else
                {
                    Log.Info($"Recording stopped, file: {_tempFilePath}");
                    LastRecordingPath = _tempFilePath;
                }
            }
            catch (Exception ex)
            {
                Log.Error("Error in recording stopped handler", ex);
            }
        }

        IsRecording = false;
        CurrentLevel = 0;
    }

    /// <summary>
    /// Converts an audio file to 16kHz mono 16-bit PCM WAV format.
    /// Used when the input device doesn't support direct 16kHz recording.
    /// </summary>
    public static string? ConvertToWhisperFormat(string inputPath)
    {
        try
        {
            var outputPath = Path.Combine(Path.GetTempPath(), $"speechy_converted_{Guid.NewGuid()}.wav");

            using var reader = new AudioFileReader(inputPath);
            var targetFormat = new WaveFormat(16000, 16, 1);

            using var resampler = new MediaFoundationResampler(reader, targetFormat);
            resampler.ResamplerQuality = 60;

            WaveFileWriter.CreateWaveFile(outputPath, resampler);

            Log.Info($"Audio converted to Whisper format: {outputPath}");
            return outputPath;
        }
        catch (Exception ex)
        {
            Log.Error("Audio conversion failed", ex);
            return null;
        }
    }

    /// <summary>
    /// Gets a list of available audio input devices.
    /// </summary>
    public static List<(int DeviceNumber, string Name)> GetInputDevices()
    {
        var devices = new List<(int, string)>();
        for (int i = 0; i < WaveInEvent.DeviceCount; i++)
        {
            var caps = WaveInEvent.GetCapabilities(i);
            devices.Add((i, caps.ProductName));
        }
        return devices;
    }

    /// <summary>
    /// Cleans up a temporary audio file.
    /// </summary>
    public static void CleanupTempFile(string? filePath)
    {
        if (string.IsNullOrEmpty(filePath)) return;
        try
        {
            if (File.Exists(filePath))
                File.Delete(filePath);
        }
        catch { }
    }

    private void Cleanup()
    {
        lock (_lock)
        {
            _writer?.Dispose();
            _writer = null;
        }
        _waveIn?.Dispose();
        _waveIn = null;
        IsRecording = false;
        CurrentLevel = 0;
    }

    public void Dispose()
    {
        Cleanup();
        GC.SuppressFinalize(this);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
