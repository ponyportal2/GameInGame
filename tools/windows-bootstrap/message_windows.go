//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

const (
	mbOK          = 0x00000000
	mbIconError   = 0x00000010
	mbIconWarning = 0x00000030
	mbIconInfo    = 0x00000040
)

var (
	user32     = syscall.NewLazyDLL("user32.dll")
	messageBox = user32.NewProc("MessageBoxW")
)

func message(kind uintptr, format string, args ...any) {
	body, _ := syscall.UTF16PtrFromString(fmt.Sprintf(format, args...))
	title, _ := syscall.UTF16PtrFromString("GameSmith")
	_, _, _ = messageBox.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), kind|mbOK)
}

func fatalf(format string, args ...any)   { message(mbIconError, format, args...) }
func warningf(format string, args ...any) { message(mbIconWarning, format, args...) }
func infof(format string, args ...any)    { message(mbIconInfo, format, args...) }
