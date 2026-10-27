// Package slug turns free text into URL-friendly slugs.
package slug

import "strings"

// Make lowercases s and replaces every run of non-alphanumeric
// characters with a single hyphen.
func Make(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else {
			b.WriteRune('-')
		}
	}
	return b.String()
}
