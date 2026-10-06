# Android patches

These patches apply to Herdr v0.9.3, commit
`7b116c05bfda646af39d2524c54e70c751f57ee8`. They are maintained by this
distribution and have not been submitted upstream.

| Patch | Purpose |
| --- | --- |
| `0001-android-target.patch` | Add Android API 24 Zig targets and NDK libc configuration; select the existing Linux process implementation and Unix daemon handling on Android; provide a Termux pane shell when `SHELL` is unset; disable upstream binary updates for Termux packages. |
| `0002-android-runtime.patch` | Exclude logind, use Termux shell and SSH configuration paths, avoid inaccessible `/tmp` fallbacks, and disable SSH connection sharing where Termux paths exceed socket limits. |

The release build verifies the pinned revision and rejects tracked source edits
outside this patch set. Remove each patch only when the pinned upstream version
provides the equivalent Android behavior, then repeat the Android runtime smoke
test in a Termux application process. A desktop Linux test or Android `run-as`
process alone does not exercise the app's Android syscall restrictions.

The x86_64 Android target exists for emulator validation. Published phone
packages target aarch64. Android desktop integration such as desktop notification
programs and X11 clipboard helpers is not provided by these patches.
