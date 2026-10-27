package main

import (
	"fmt"
	"os"
	"strings"

	"t4lsandbox/internal/slug"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slug <text>")
		os.Exit(2)
	}
	fmt.Println(slug.Make(strings.Join(os.Args[1:], " ")))
}
