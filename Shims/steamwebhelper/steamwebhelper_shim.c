/*
 * Archway steamwebhelper shim.
 *
 * Wine's macOS driver drops pixels that one process draws into a window owned
 * by another (Wine bugs 35456 and 60263). Chromium's GPU process does exactly
 * that for Steam's client UI, so the window stays black. Archway installs
 * this shim at Steam's webhelper path and moves Valve's helper next to it; the
 * shim starts that helper with --in-process-gpu so the compositor draws from
 * the process that owns the window.
 *
 * Build: Shims/steamwebhelper/build.sh
 */

#include <windows.h>
#include <wchar.h>

static const wchar_t real_name[] = L"steamwebhelper.real.exe";
static const wchar_t extra_flag[] = L" --in-process-gpu";

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR unused, int show)
{
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, path, MAX_PATH);
    wchar_t *slash = wcsrchr(path, L'\\');
    if (!length || length >= MAX_PATH || !slash || (size_t)(slash + 1 - path) + wcslen(real_name) >= MAX_PATH)
        return 1;
    wcscpy(slash + 1, real_name);

    /* Keep the original arguments verbatim; only argv[0] is replaced. */
    const wchar_t *arguments = GetCommandLineW();
    if (*arguments == L'"') {
        arguments = wcschr(arguments + 1, L'"');
        arguments = arguments ? arguments + 1 : L"";
    } else {
        while (*arguments && *arguments != L' ' && *arguments != L'\t') arguments++;
    }

    /* Chromium child processes start the real helper directly; add the flag
       only to the browser process in case one is ever routed through here. */
    const wchar_t *flag = wcsstr(arguments, L"--type=") ? L"" : extra_flag;
    size_t size = wcslen(path) + wcslen(arguments) + wcslen(flag) + 3;
    wchar_t *command = HeapAlloc(GetProcessHeap(), 0, size * sizeof(wchar_t));
    if (!command) return 1;
    wsprintfW(command, L"\"%s\"%s%s", path, arguments, flag);

    /* Steam tracks and terminates the shim's PID; the job ends the real helper
       with it so no orphaned browser keeps running. */
    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
    }

    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    GetStartupInfoW(&startup);
    if (!CreateProcessW(path, command, NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, &startup, &process))
        return 2;
    if (job) AssignProcessToJobObject(job, process.hProcess);
    ResumeThread(process.hThread);
    CloseHandle(process.hThread);

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(process.hProcess, &code);
    return (int)code;
}
