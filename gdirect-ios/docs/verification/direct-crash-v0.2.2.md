# Direct download lifecycle crash

User incident: GDirect 0.2.1 build 3, iOS 27.2, EXC_BAD_ACCESS/SIGSEGV on utility worker in strlen. App binary UUID matches supplied incident (440ed372-141d-383a-9db8-c6ae3534413b).

Disassembly of matching IPA: caller offset 0x17da28 dereferences a Pref key; its caller constructs the http-proxy option handler. aria2 1.37.0 Platform::tearDown deletes OptionParser and PrefFactory; PrefFactory and global PrefPtr values cannot be reconstructed by another libraryInit call. Our bridge initialized/deinitialized the library per download.

A native regression linked against real Linux libaria2 runs three sessions against a local closed port. Before fix: exit 139 at session 2. After fix: exit 0, all three return normal download errors. No network/account dependency. This isolates global lifecycle from iOS scheduling and Google routing.

Fix: initialize aria2 once for process lifetime, serialize bridge calls, finalize each per-download session normally. OS reclaims process-global resources when the app exits; libraryDeinit must not run between transfers. Keep route pointers scoped to each synchronous call.

Actual-device verification remains required after installing the rebuilt IPA.
