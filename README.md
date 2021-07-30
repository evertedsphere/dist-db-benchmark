benchmark for (distributed) databases that speak the postgres wire protocol.

the benchmark load configuration consists of parameters s, r, and k₀, k₁, k₂,
…, kₙ. additionally, a postgres connection string is required to specify a
database against which the benchmark will be run.

based on these, it runs each benchmark once with k₀ threads running in
parallel, then with k₁ threads, and so on. each of these benchmark executions
is run s times with the same value of kᵢ, each of these executions being called
a set, and the statistics collected together. each set consists of kᵢ threads,
each executing one query r times one after the other.

```
# install cabal and ghc first, via ghcup or your system package manager

# example configuration

export METADATA_BENCHMARK_NUM_SETS=5                # s
export METADATA_BENCHMARK_NUM_THREADS_PER_SET=1,2,4 # k₀, k₁, …, kₙ
export METADATA_BENCHMARK_NUM_RUNS_PER_THREAD=4     # r

export METADATA_BENCHMARK_CONN_STRING="host=localhost port=5433 user=yugabyte"

# add a line to ~/.pgpass to specify the password as follows:
# localhost:5433:*:yugabyte:password
# the benchmark picks it up from there

# set up the database
psql METADATA_BENCHMARK_CONN_STRING -f init.sql

# finally, run the benchmark
cabal new-run
```
