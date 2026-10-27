# Playbook: perf

Default mode: ODD only, plus the regression check. A performance claim is a number measured twice with the same harness: once on the old code, once on the new. A number you cannot explain is not a result yet.

## Steps

1. **Measure the baseline before touching the code.** Write the measurement first (a benchmark, or a timed run of the real entry point) and run it on the current code. Use the input the user named. If it takes too long, measure at growing sizes (for example n, 2n, 4n) and report the growth; do not skip the baseline or quote the user's number as if you had measured it.
2. **Explain the number.** Before believing it, say why it has that value: the complexity (time doubles or quadruples when the input doubles), the allocations (`go test -bench . -benchmem`), what dominates a profile (`-cpuprofile`, `go tool pprof -top`). Distrust a result that is too good: dead-code elimination, a warm cache, a smaller input than you think.
3. **Change one thing** at the cause the explanation points to. Keep the behavior: the output must not change unless the user asked for it.
4. **Measure again with the same harness and the same input**, several runs (`-count 5`; `benchstat` when installed). Explain the new number the same way: why this value and not lower.
5. **Keep the measurement** when the repo has a place for benchmarks (a `Benchmark` in the package's tests). Delete only throwaway timing scripts.
6. **Verify behavior**: the existing tests and the regression check (router section 7) with the entry points that reach the changed code, including a large input.

## Language-specific checks

- **Go**: `go test -run '^$' -bench <Name> -benchmem -count 5 ./<pkg>`. Use the `cc-skills-golang` skills `golang-benchmark` and `golang-performance` for profiling and optimization patterns.
- **TypeScript**: time the real entry point (`hyperfine` when installed, otherwise repeated timed runs), with the same input before and after.

## Reply format

- The cause, with the explanation of the baseline number.
- A before/after table from the same command and input, with units and the number of runs:

  ```
  | input | before | after | runs |
  ```
- Why the new number has the value it has.
- The regression line.
