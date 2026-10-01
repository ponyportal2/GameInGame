//go:build !windows

package main

import "fmt"

func fatalf(format string, args ...any)   { fmt.Printf("ERROR: "+format+"\n", args...) }
func warningf(format string, args ...any) { fmt.Printf("WARNING: "+format+"\n", args...) }
func infof(format string, args ...any)    { fmt.Printf("INFO: "+format+"\n", args...) }
