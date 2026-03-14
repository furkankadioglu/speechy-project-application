using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using Speechy.Helpers;
using Speechy.Models;

namespace Speechy.Services;

/// <summary>
/// Global hotkey manager using a low-level keyboard hook (WH_KEYBOARD_LL).
/// Supports modifier-only hotkeys for push-to-talk and toggle-to-talk modes.
/// Matches the macOS HotkeyManager behavior with activation delay.
/// </summary>
public class HotkeyManager : IDisposable
{
    /// <summary>
    /// Called when recording should start. Parameters: (language, flag).
    /// </summary>
    public event Action<string, string>? OnRecordingStart;

    /// <summary>
    /// Called when recording should stop.
    /// </summary>
    public event Action? OnRecordingStop;

    private IntPtr _hookId = IntPtr.Zero;
    private NativeMethods.LowLevelKeyboardProc? _hookCallback;
    private readonly DispatcherTimer _activationTimer;
    private HotkeyConfig? _pendingSlot;
    private bool _isRecording;
    private bool _isToggleRecording;
    private HotkeyConfig? _activeSlot;
    private ModifierKeys _currentModifiers;
    private bool _disposed;

    // Track which physical keys are currently held
    private readonly HashSet<int> _heldKeys = new();

    public bool IsRecording => _isRecording;

    public HotkeyManager()
    {
        _activationTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(150)
        };
        _activationTimer.Tick += OnActivationTimerTick;
    }

    /// <summary>
    /// Installs the low-level keyboard hook. Must be called from the UI thread.
    /// </summary>
    public void Install()
    {
        if (_hookId != IntPtr.Zero) return;

        _hookCallback = HookCallback;
        using var curProcess = Process.GetCurrentProcess();
        using var curModule = curProcess.MainModule!;

        _hookId = NativeMethods.SetWindowsHookEx(
            NativeMethods.WH_KEYBOARD_LL,
            _hookCallback,
            NativeMethods.GetModuleHandle(curModule.ModuleName),
            0);

        if (_hookId == IntPtr.Zero)
        {
            Log.Error($"Failed to install keyboard hook. Error: {Marshal.GetLastWin32Error()}");
        }
        else
        {
            Log.Info("Keyboard hook installed");
        }
    }

    /// <summary>
    /// Removes the keyboard hook.
    /// </summary>
    public void Uninstall()
    {
        if (_hookId != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
            _hookCallback = null;
            Log.Info("Keyboard hook uninstalled");
        }
    }

    /// <summary>
    /// Updates the activation delay from settings.
    /// </summary>
    public void UpdateActivationDelay()
    {
        var delay = SettingsManager.Instance.ActivationDelay;
        _activationTimer.Interval = TimeSpan.FromSeconds(delay > 0 ? delay : 0.15);
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var vkCode = Marshal.ReadInt32(lParam);
            var isKeyDown = wParam == (IntPtr)NativeMethods.WM_KEYDOWN || wParam == (IntPtr)NativeMethods.WM_SYSKEYDOWN;
            var isKeyUp = wParam == (IntPtr)NativeMethods.WM_KEYUP || wParam == (IntPtr)NativeMethods.WM_SYSKEYUP;

            // Check for Escape to cancel toggle recording
            if (isKeyDown && vkCode == NativeMethods.VK_ESCAPE && _isToggleRecording)
            {
                StopRecording();
                return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
            }

            // Track modifier keys
            var modifier = VkCodeToModifier(vkCode);
            if (modifier != Models.ModifierKeys.None)
            {
                if (isKeyDown)
                {
                    if (!_heldKeys.Contains(vkCode))
                    {
                        _heldKeys.Add(vkCode);
                        _currentModifiers |= modifier;
                        OnModifiersChanged(true);
                    }
                }
                else if (isKeyUp)
                {
                    _heldKeys.Remove(vkCode);
                    // Only clear modifier if no other key with same modifier is held
                    if (!IsModifierStillHeld(modifier))
                    {
                        _currentModifiers &= ~modifier;
                    }
                    OnModifiersChanged(false);
                }
            }
            else
            {
                // Non-modifier key pressed - cancel any pending activation
                if (isKeyDown)
                {
                    _activationTimer.Stop();
                    _pendingSlot = null;
                }
            }
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void OnModifiersChanged(bool keyDown)
    {
        if (keyDown)
        {
            // Check if current modifiers match any slot
            var matchedSlot = FindMatchingSlot(_currentModifiers);
            if (matchedSlot != null)
            {
                if (matchedSlot.Mode == HotkeyMode.ToggleToTalk && _isToggleRecording && _activeSlot != null &&
                    _activeSlot.Modifiers == matchedSlot.Modifiers)
                {
                    // Same toggle slot pressed again - stop recording
                    // Use a small delay to prevent accidental double-taps
                    _pendingSlot = null;
                    _activationTimer.Stop();
                    StopRecording();
                    return;
                }

                // Start activation delay timer
                _pendingSlot = matchedSlot;
                _activationTimer.Stop();
                UpdateActivationDelay();
                _activationTimer.Start();
            }
        }
        else
        {
            // Key released
            if (_pendingSlot != null)
            {
                // Check if the modifiers no longer match the pending slot
                if (_currentModifiers != _pendingSlot.Modifiers)
                {
                    _activationTimer.Stop();
                    _pendingSlot = null;
                }
            }

            // For push-to-talk: release stops recording
            if (_isRecording && !_isToggleRecording && _activeSlot != null)
            {
                if (!_currentModifiers.HasFlag(_activeSlot.Modifiers) || _currentModifiers != _activeSlot.Modifiers)
                {
                    StopRecording();
                }
            }
        }
    }

    private void OnActivationTimerTick(object? sender, EventArgs e)
    {
        _activationTimer.Stop();

        if (_pendingSlot == null) return;

        // Verify modifiers still match
        if (_currentModifiers != _pendingSlot.Modifiers)
        {
            _pendingSlot = null;
            return;
        }

        var slot = _pendingSlot;
        _pendingSlot = null;

        if (slot.Mode == HotkeyMode.ToggleToTalk)
        {
            if (!_isRecording)
            {
                StartRecording(slot);
                _isToggleRecording = true;
            }
            // Toggle stop is handled in OnModifiersChanged
        }
        else
        {
            // Push-to-talk: start recording
            if (!_isRecording)
            {
                StartRecording(slot);
                _isToggleRecording = false;
            }
        }
    }

    private void StartRecording(HotkeyConfig slot)
    {
        if (_isRecording) return;

        _isRecording = true;
        _activeSlot = slot;
        var flag = SupportedLanguages.GetFlag(slot.Language);
        Log.Info($"Hotkey recording start - lang: {slot.Language}, mode: {slot.Mode}, modifiers: {slot.DisplayName}");
        OnRecordingStart?.Invoke(slot.Language, flag);
    }

    private void StopRecording()
    {
        if (!_isRecording) return;

        _isRecording = false;
        _isToggleRecording = false;
        _activeSlot = null;
        Log.Info("Hotkey recording stop");
        OnRecordingStop?.Invoke();
    }

    private HotkeyConfig? FindMatchingSlot(ModifierKeys modifiers)
    {
        if (modifiers == Models.ModifierKeys.None) return null;

        var settings = SettingsManager.Instance;

        var slots = new[] { settings.Slot1, settings.Slot2, settings.Slot3, settings.Slot4 };
        foreach (var slot in slots)
        {
            if (slot.IsEnabled && slot.Modifiers == modifiers)
            {
                return slot;
            }
        }

        return null;
    }

    private bool IsModifierStillHeld(ModifierKeys modifier)
    {
        foreach (var vk in _heldKeys)
        {
            if (VkCodeToModifier(vk) == modifier)
                return true;
        }
        return false;
    }

    private static ModifierKeys VkCodeToModifier(int vkCode) => vkCode switch
    {
        NativeMethods.VK_LSHIFT or NativeMethods.VK_RSHIFT or NativeMethods.VK_SHIFT => Models.ModifierKeys.Shift,
        NativeMethods.VK_LCONTROL or NativeMethods.VK_RCONTROL or NativeMethods.VK_CONTROL => Models.ModifierKeys.Ctrl,
        NativeMethods.VK_LMENU or NativeMethods.VK_RMENU or NativeMethods.VK_MENU => Models.ModifierKeys.Alt,
        NativeMethods.VK_LWIN or NativeMethods.VK_RWIN => Models.ModifierKeys.Win,
        _ => Models.ModifierKeys.None
    };

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _activationTimer.Stop();
        Uninstall();
        GC.SuppressFinalize(this);
    }
}
