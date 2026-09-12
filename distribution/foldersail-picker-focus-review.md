# Observe the single native picker focus request

Original run 34701759385, source cc8cf6db31716217b3deacf5ac27253f118d2cf0,
completed actual 84-byte Unicode file Copy and Move, verified both persisted and
visible receipts, opened the owned PickerHost Save As window 66104 / PID 5208, and
read back the exact selected CSV path. Its next picker-button assertion failed
before any Space input. The subsequent original failure tree shows Save as a
visible, enabled, keyboard-focusable standard Button with keyboard focus.
The generic original error did not retain the button HWND or the property that
failed. A delayed focus observation is therefore a candidate, not an established
root cause or a successful native export.

The external consumer helper now observes the one existing SetFocus request for
at most 20 reads, spaced 50 ms apart, before its sole ordinary Space input. Every
read still requires the same original nonzero button HWND, process, ID, name,
class, enabled/visible/focusable state and owned foreground window. Identity and
ownership changes fail immediately. It never repeats SetFocus or input. The
compiled adapter independently requires actual native focus immediately before
SendInput. A timeout still fails the workflow. This changes no product code.

Bounded focus observations and exact refused provider properties are retained in
the existing trace so a further native failure can distinguish missing HWND,
identity and focus. Original copy/move/CSV confirmation/recovery/metadata-clear,
normal close, uninstall and both package qualification requirements remain.

Verification: a production-helper test with delayed focus first failed against
the original implementation, then passed with exactly one focus request and one
input. Original rejection cases plus delayed identity drift, 20-read timeout,
missing native HWND and retained false/false/true observations pass. The compiled
native input boundary’s 16 cases also pass. These replay tests do not claim that
the next actual Windows run has succeeded.
