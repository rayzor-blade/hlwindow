/* The window backend's event-loop hook, for an app that links hlwindow's
 * static library from C. See xwindow's CONTRIBUTING.md, "The host's hook". */
#ifndef XWINDOW_H
#define XWINDOW_H

#ifdef __cplusplus
extern "C" {
#endif

/* The program pumps the event loop inside open, poll and wait. 0 when
 * attached, -1 when not; always -1 on iOS, which cannot pump. Optional on
 * Android and desktops, where the first window attaches it. */
int xwindow_attach_pump(void);

/* Runs the event loop, calling turn(data) for each of the program's turns
 * until it returns 0. A window opens only in a turn; poll and wait do not
 * block. Returns 0 when the loop ends, which on iOS it never does, and -1
 * when it cannot run. */
int xwindow_run_turns(int (*turn)(void *data), void *data);

/* On Android, the app's program entry, which the library's android_main
 * calls on the activity's thread once it has kept the AndroidApp. */
void xwindow_main(void);

#ifdef __cplusplus
}
#endif

#endif
