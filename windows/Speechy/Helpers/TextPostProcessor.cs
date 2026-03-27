using Speechy.Models;

namespace Speechy.Helpers;

/// <summary>
/// Post-processes transcription output based on the selected ModalConfig.
/// </summary>
public static class TextPostProcessor
{
    /// <summary>
    /// Applies paragraph breaks to text by grouping every 3 sentences together.
    /// </summary>
    public static string ApplyParagraphBreaks(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return text;

        var sentences = new List<string>();
        var current = new System.Text.StringBuilder();
        var chars = text.ToCharArray();

        for (int i = 0; i < chars.Length; i++)
        {
            char c = chars[i];
            current.Append(c);

            bool isTerminator = c == '.' || c == '!' || c == '?' || c == '\u3002' || c == '\uff01' || c == '\uff1f';
            bool nextIsSpace = (i + 1 < chars.Length) && char.IsWhiteSpace(chars[i + 1]);
            bool isLast = i == chars.Length - 1;

            if (isTerminator && (nextIsSpace || isLast))
            {
                var s = current.ToString().Trim();
                if (!string.IsNullOrEmpty(s))
                    sentences.Add(s);
                current.Clear();
            }
        }

        var remaining = current.ToString().Trim();
        if (!string.IsNullOrEmpty(remaining))
            sentences.Add(remaining);

        if (sentences.Count <= 1) return text;

        const int groupSize = 3;
        var paragraphs = new List<string>();
        for (int i = 0; i < sentences.Count; i += groupSize)
        {
            var end = Math.Min(i + groupSize, sentences.Count);
            var group = string.Join(" ", sentences.Skip(i).Take(end - i));
            paragraphs.Add(group);
        }

        return string.Join("\n\n", paragraphs);
    }

    /// <summary>
    /// Applies post-processing based on the selected ModalConfig.
    /// Currently only Paragraphs requires post-processing; others rely on whisper --prompt.
    /// </summary>
    public static string Apply(string text, ModalConfig config)
    {
        return config == ModalConfig.Paragraphs ? ApplyParagraphBreaks(text) : text;
    }
}
