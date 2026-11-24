//go:build !windows

package main

// freeDiskBytes is only implemented on Windows for now; -1 means "unknown",
// and the free-space guard is then skipped.
func freeDiskBytes(string) int64 { return -1 }
