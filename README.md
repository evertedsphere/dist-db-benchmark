benchmark for (distributed) databases that speak the postgres wire protocol.

to run N _sets_ of benchmarks, each set consisting of multiple threads running
in parallel, each thread executing one query n times one after the other:

```
# install cabal and ghc first, via ghcup or your system package manager

export METADATA_BENCHMARK_NUM_SETS=<N>
export METADATA_BENCHMARK_NUM_RUNS_PER_THREAD=<n>
export METADATA_BENCHMARK_CONN_STRING=<pg conn string>

psql METADATA_BENCHMARK_CONN_STRING -f init.sql

cabal new-run
```

the number of threads is first 1, then 2, and then 4. runtime configuration for
this may be added later.
