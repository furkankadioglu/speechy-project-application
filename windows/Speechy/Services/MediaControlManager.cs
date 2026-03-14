using Speechy.Helpers;

namespace Speechy.Services;

/// <summary>
/// Manages media playback control - pauses/resumes media during recording.
/// Uses VK_MEDIA_PLAY_PAUSE via keybd_event to control media players.
/// </summary>
public class MediaControlManager
{
    private bool _didPauseMedia;

    /// <summary>
    /// Gets whether media was paused by this manager and should be resumed.
    /// </summary>
    public bool DidPauseMedia => _didPauseMedia;

    /// <summary>
    /// Pauses media playback if currently playing and setting is enabled.
    /// Sends VK_MEDIA_PLAY_PAUSE keystroke.
    /// </summary>
    public void PauseMediaIfNeeded()
    {
        if (!SettingsManager.Instance.PauseMediaDuringRecording)
        {
            _didPauseMedia = false;
            return;
        }

        try
        {
            // Check if media is likely playing by querying the system media transport controls.
            // Since there's no simple synchronous API for this in pure Win32,
            // we optimistically send the pause command and track state.
            if (IsMediaLikelyPlaying())
            {
                SendMediaPlayPause();
                _didPauseMedia = true;
                Log.Info("Media paused for recording");
            }
            else
            {
                _didPauseMedia = false;
            }
        }
        catch (Exception ex)
        {
            Log.Error("Failed to pause media", ex);
            _didPauseMedia = false;
        }
    }

    /// <summary>
    /// Resumes media playback if it was paused by PauseMediaIfNeeded.
    /// </summary>
    public void ResumeMediaIfNeeded()
    {
        if (!_didPauseMedia) return;

        try
        {
            SendMediaPlayPause();
            _didPauseMedia = false;
            Log.Info("Media resumed after recording");
        }
        catch (Exception ex)
        {
            Log.Error("Failed to resume media", ex);
        }
    }

    /// <summary>
    /// Sends a VK_MEDIA_PLAY_PAUSE keystroke via keybd_event.
    /// </summary>
    private static void SendMediaPlayPause()
    {
        NativeMethods.keybd_event(NativeMethods.VK_MEDIA_PLAY_PAUSE, 0, 0, UIntPtr.Zero);
        NativeMethods.keybd_event(NativeMethods.VK_MEDIA_PLAY_PAUSE, 0, NativeMethods.KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    /// <summary>
    /// Heuristic check if media is likely playing.
    /// Uses the Windows Session Manager API via a background check.
    /// As a simple heuristic, we check if common media processes are running.
    /// </summary>
    private static bool IsMediaLikelyPlaying()
    {
        try
        {
            var mediaProcesses = new[]
            {
                "spotify", "wmplayer", "vlc", "musicbee", "foobar2000",
                "groove", "itunes", "chrome", "msedge", "firefox", "opera"
            };

            var running = System.Diagnostics.Process.GetProcesses();
            foreach (var proc in running)
            {
                try
                {
                    var name = proc.ProcessName.ToLowerInvariant();
                    foreach (var mediaProc in mediaProcesses)
                    {
                        if (name.Contains(mediaProc))
                        {
                            return true;
                        }
                    }
                }
                catch
                {
                    // Process may have exited
                }
            }
        }
        catch (Exception ex)
        {
            Log.Error("Error checking media status", ex);
        }

        return false;
    }
}
