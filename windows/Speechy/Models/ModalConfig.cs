namespace Speechy.Models;

/// <summary>
/// Transcription style preset sent to Whisper as initial prompt hint.
/// Mirrors macOS ModalConfigType enum.
/// </summary>
public enum ModalConfig
{
    Default,
    NoPunctuation,
    NoCapitalize,
    AllLowercase,
    Formal,
    Paragraphs,
    MeetingNotes
}

public static class ModalConfigExtensions
{
    public static string DisplayName(this ModalConfig config) => config switch
    {
        ModalConfig.Default       => "Default",
        ModalConfig.NoPunctuation => "No Punctuation",
        ModalConfig.NoCapitalize  => "No Capitalization",
        ModalConfig.AllLowercase  => "All Lowercase",
        ModalConfig.Formal        => "Formal / Corporate",
        ModalConfig.Paragraphs    => "Paragraph Breaks",
        ModalConfig.MeetingNotes  => "Meeting Notes",
        _                         => "Default"
    };

    public static string Description(this ModalConfig config) => config switch
    {
        ModalConfig.Default       => "Standard transcription, no style changes",
        ModalConfig.NoPunctuation => "Output without any punctuation marks",
        ModalConfig.NoCapitalize  => "Don't capitalize the start of sentences",
        ModalConfig.AllLowercase  => "Write everything in lowercase letters",
        ModalConfig.Formal        => "Use formal and corporate language style",
        ModalConfig.Paragraphs    => "Break transcription into paragraphs by topic",
        ModalConfig.MeetingNotes  => "Format output as structured meeting notes",
        _                         => ""
    };

    public static string PromptHint(this ModalConfig config) => config switch
    {
        ModalConfig.Default       => "",
        ModalConfig.NoPunctuation => "no punctuation",
        ModalConfig.NoCapitalize  => "no capitalization",
        ModalConfig.AllLowercase  => "all lowercase",
        ModalConfig.Formal        => "formal corporate professional language",
        ModalConfig.Paragraphs    => "new paragraph for each topic",
        ModalConfig.MeetingNotes  => "[Meeting Notes]",
        _                         => ""
    };

    public static string Icon(this ModalConfig config) => config switch
    {
        ModalConfig.Default       => "\uE8A4", // TextBlock (Segoe MDL2)
        ModalConfig.NoPunctuation => "\uE8D2", // Font
        ModalConfig.NoCapitalize  => "\uE8D2",
        ModalConfig.AllLowercase  => "\uE8D2",
        ModalConfig.Formal        => "\uE821", // Library
        ModalConfig.Paragraphs    => "\uE8A4",
        ModalConfig.MeetingNotes  => "\uE7C3", // Page
        _                         => "\uE8A4"
    };

    public static string RawValue(this ModalConfig config) => config switch
    {
        ModalConfig.Default       => "default",
        ModalConfig.NoPunctuation => "noPunctuation",
        ModalConfig.NoCapitalize  => "noCapitalize",
        ModalConfig.AllLowercase  => "allLowercase",
        ModalConfig.Formal        => "formal",
        ModalConfig.Paragraphs    => "paragraphs",
        ModalConfig.MeetingNotes  => "meetingNotes",
        _                         => "default"
    };

    public static ModalConfig FromRawValue(string? raw) => raw switch
    {
        "noPunctuation" => ModalConfig.NoPunctuation,
        "noCapitalize"  => ModalConfig.NoCapitalize,
        "allLowercase"  => ModalConfig.AllLowercase,
        "formal"        => ModalConfig.Formal,
        "paragraphs"    => ModalConfig.Paragraphs,
        "meetingNotes"  => ModalConfig.MeetingNotes,
        _               => ModalConfig.Default
    };

    public static IEnumerable<ModalConfig> AllCases() =>
        Enum.GetValues<ModalConfig>();
}
