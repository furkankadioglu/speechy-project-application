using System.Runtime.InteropServices;
using System.Windows;
using Speechy.Helpers;

namespace Speechy.Services;

/// <summary>
/// Copies text to clipboard and simulates Ctrl+V to auto-paste into the active application.
/// </summary>
public static class AutoPasteManager
{
    /// <summary>
    /// Copies text to clipboard and simulates Ctrl+V paste.
    /// </summary>
    /// <param name="text">The text to paste.</param>
    public static void CopyAndPaste(string text)
    {
        try
        {
            // Copy to clipboard (must be on STA thread)
            if (Application.Current?.Dispatcher != null)
            {
                Application.Current.Dispatcher.Invoke(() =>
                {
                    Clipboard.SetText(text);
                });
            }
            else
            {
                Clipboard.SetText(text);
            }

            // Small delay to ensure clipboard is updated
            Thread.Sleep(50);

            // Simulate Ctrl+V using SendInput
            SimulateCtrlV();

            Log.Info($"Auto-pasted text ({text.Length} chars)");
        }
        catch (Exception ex)
        {
            Log.Error("Auto-paste failed", ex);
        }
    }

    /// <summary>
    /// Copies text to clipboard without pasting.
    /// </summary>
    public static void CopyToClipboard(string text)
    {
        try
        {
            if (Application.Current?.Dispatcher != null)
            {
                Application.Current.Dispatcher.Invoke(() =>
                {
                    Clipboard.SetText(text);
                });
            }
            else
            {
                Clipboard.SetText(text);
            }
            Log.Info($"Copied to clipboard ({text.Length} chars)");
        }
        catch (Exception ex)
        {
            Log.Error("Clipboard copy failed", ex);
        }
    }

    /// <summary>
    /// Simulates Ctrl+V keystroke using SendInput.
    /// </summary>
    private static void SimulateCtrlV()
    {
        var inputs = new NativeMethods.INPUT[4];

        // Ctrl down
        inputs[0] = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            u = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = (ushort)NativeMethods.VK_CONTROL,
                    dwFlags = 0
                }
            }
        };

        // V down
        inputs[1] = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            u = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = 0x56, // V key
                    dwFlags = 0
                }
            }
        };

        // V up
        inputs[2] = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            u = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = 0x56,
                    dwFlags = NativeMethods.KEYEVENTF_KEYUP
                }
            }
        };

        // Ctrl up
        inputs[3] = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            u = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = (ushort)NativeMethods.VK_CONTROL,
                    dwFlags = NativeMethods.KEYEVENTF_KEYUP
                }
            }
        };

        var size = Marshal.SizeOf<NativeMethods.INPUT>();
        NativeMethods.SendInput((uint)inputs.Length, inputs, size);
    }
}
