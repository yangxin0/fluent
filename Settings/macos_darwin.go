package main

/*
#cgo LDFLAGS: -framework Carbon -framework CoreFoundation
#include <Carbon/Carbon.h>
#include <stdlib.h>
#include <string.h>

// Whether Input Sources has an input source with this id; with enabledOnly,
// only once it is added in System Settings ▸ Keyboard ▸ Input Sources.
static int hasInputSource(const char *id, int enabledOnly) {
	CFStringRef sid = CFStringCreateWithCString(NULL, id, kCFStringEncodingUTF8);
	const void *keys[] = { kTISPropertyInputSourceID };
	const void *values[] = { sid };
	CFDictionaryRef filter = CFDictionaryCreate(NULL, keys, values, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFArrayRef list = TISCreateInputSourceList(filter, !enabledOnly);
	int found = list != NULL && CFArrayGetCount(list) > 0;
	if (list != NULL) CFRelease(list);
	CFRelease(filter);
	CFRelease(sid);
	return found;
}

static char *copyUTF8(CFStringRef s) {
	if (s == NULL) return NULL;
	CFIndex size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
	char *out = malloc(size);
	if (!CFStringGetCString(s, out, size, kCFStringEncodingUTF8)) { free(out); return NULL; }
	return out;
}

// The id of the input source typing goes to now; the caller frees it.
static char *currentInputSource(void) {
	TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
	if (source == NULL) return NULL;
	char *id = copyUTF8((CFStringRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceID));
	CFRelease(source);
	return id;
}

// The first of the user's preferred languages, as "zh-Hans-CN".
static char *preferredLanguage(void) {
	CFArrayRef languages = CFLocaleCopyPreferredLanguages();
	char *first = NULL;
	if (languages != NULL && CFArrayGetCount(languages) > 0) {
		first = copyUTF8((CFStringRef)CFArrayGetValueAtIndex(languages, 0));
	}
	if (languages != NULL) CFRelease(languages);
	return first;
}

// Whether the Mac is in dark mode now (its "Auto" switches this too).
static int darkMode(void) {
	CFStringRef style = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("AppleInterfaceStyle"), kCFPreferencesAnyApplication);
	int dark = style != NULL && CFGetTypeID(style) == CFStringGetTypeID()
		&& CFStringCompare(style, CFSTR("Dark"), kCFCompareCaseInsensitive) == kCFCompareEqualTo;
	if (style != NULL) CFRelease(style);
	return dark;
}

static void postDistributed(const char *name) {
	CFStringRef n = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(), n, NULL, NULL, true);
	CFRelease(n);
}
*/
import "C"

import (
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
)

// inputSourceID is the input method's id in Input Sources.
const inputSourceID = "com.yangxin.inputmethod.Fluent"

// Text Input Sources wants the main thread.
func inputSourceAdded() bool {
	return application.InvokeSyncWithResult(func() bool {
		id := C.CString(inputSourceID)
		defer C.free(unsafe.Pointer(id))
		return C.hasInputSource(id, 1) != 0
	})
}

func inputSourceSelected() bool {
	return application.InvokeSyncWithResult(func() bool {
		id := C.currentInputSource()
		if id == nil {
			return false
		}
		defer C.free(unsafe.Pointer(id))
		return C.GoString(id) == inputSourceID
	})
}

func preferredLanguage() string {
	lang := C.preferredLanguage()
	if lang == nil {
		return "en"
	}
	defer C.free(unsafe.Pointer(lang))
	return C.GoString(lang)
}

func darkMode() bool { return C.darkMode() != 0 }

func postDistributed(name string) {
	n := C.CString(name)
	defer C.free(unsafe.Pointer(n))
	C.postDistributed(n)
}
