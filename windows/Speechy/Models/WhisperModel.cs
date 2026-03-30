namespace Speechy.Models;

/// <summary>
/// Available Whisper model types, matching the macOS ModelType enum.
/// Only Medium and Large models are shown — Fast (Base) and Accurate (Small)
/// were removed for consistency and quality reasons.
/// </summary>
public enum WhisperModel
{
    Precise,
    Ultimate
}

/// <summary>
/// Extension methods providing display info, download URLs, and file sizes for each model.
/// </summary>
public static class WhisperModelExtensions
{
    /// <summary>
    /// Gets the user-friendly display name for the model.
    /// </summary>
    public static string DisplayName(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => "Precise (Medium)",
        WhisperModel.Ultimate => "Ultimate (Large)",
        _ => "Unknown"
    };

    /// <summary>
    /// Gets the description text for the model.
    /// </summary>
    public static string Description(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => "Balanced accuracy and speed",
        WhisperModel.Ultimate => "Maximum accuracy, requires more resources",
        _ => ""
    };

    /// <summary>
    /// Gets the ggml binary file name for the model.
    /// </summary>
    public static string FileName(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => "ggml-medium.bin",
        WhisperModel.Ultimate => "ggml-large-v3.bin",
        _ => "ggml-medium.bin"
    };

    /// <summary>
    /// Gets the HuggingFace download URL for the model.
    /// </summary>
    public static string DownloadUrl(this WhisperModel model) =>
        $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{model.FileName()}";

    /// <summary>
    /// Gets the human-readable file size string.
    /// </summary>
    public static string SizeDescription(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => "~1.5 GB",
        WhisperModel.Ultimate => "~3.1 GB",
        _ => "Unknown"
    };

    /// <summary>
    /// Gets the approximate file size in bytes.
    /// </summary>
    public static long FileSize(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => 1_500_000_000L,
        WhisperModel.Ultimate => 3_100_000_000L,
        _ => 0L
    };

    /// <summary>
    /// Gets the raw value string (used for serialization).
    /// </summary>
    public static string RawValue(this WhisperModel model) => model switch
    {
        WhisperModel.Precise => "medium",
        WhisperModel.Ultimate => "large-v3",
        _ => "medium"
    };

    /// <summary>
    /// Parses a raw value string back to a WhisperModel enum value.
    /// </summary>
    public static WhisperModel FromRawValue(string rawValue) => rawValue switch
    {
        "medium" => WhisperModel.Precise,
        "large-v3" => WhisperModel.Ultimate,
        // Legacy values fallback to Precise
        "base" => WhisperModel.Precise,
        "small" => WhisperModel.Precise,
        _ => WhisperModel.Precise
    };
}
