benchmark for (distributed) databases that speak the postgres wire protocol,
specifically testing partition-aware query performance at present.

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

export METADATA_BENCHMARK_CONN_STRING="..."

# add a line to ~/.pgpass to specify the password as follows:
# host:port:*:user:pass
# the benchmark picks it up from there

# set up the database
psql METADATA_BENCHMARK_CONN_STRING -f init.sql

# finally, run the benchmark
cabal new-run
```

example output:

```
running test: update, one row, non-partitioned (4 sets of 1 threads × 5 runs each)
     first run:  n =   4, mean   9801.9 ms, stddev     46.1 ms, skewness      0.2 ms
  steady state:  n =  16, mean    231.3 ms, stddev     13.5 ms, skewness      3.6 ms

running test: update, one row, non-partitioned (4 sets of 2 threads × 5 runs each)
     first run:  n =   8, mean   9796.4 ms, stddev     47.7 ms, skewness      0.7 ms
  steady state:  n =  32, mean    279.5 ms, stddev     41.6 ms, skewness      0.1 ms

running test: update, one row, non-partitioned (4 sets of 4 threads × 5 runs each)
     first run:  n =  16, mean   9804.4 ms, stddev     34.3 ms, skewness     -0.8 ms
  steady state:  n =  64, mean    296.6 ms, stddev     41.3 ms, skewness     -0.5 ms

running test: update, one row, partitioned (4 sets of 1 threads × 5 runs each)
     first run:  n =   4, mean  26968.4 ms, stddev     78.9 ms, skewness     -1.1 ms
  steady state:  n =  16, mean    584.3 ms, stddev     75.3 ms, skewness     -0.6 ms

running test: update, one row, partitioned (4 sets of 2 threads × 5 runs each)
     first run:  n =   8, mean  26942.6 ms, stddev     86.2 ms, skewness     -0.6 ms
  steady state:  n =  32, mean    601.6 ms, stddev     67.5 ms, skewness      0.4 ms

running test: update, one row, partitioned (4 sets of 4 threads × 5 runs each)
     first run:  n =  16, mean  26987.8 ms, stddev    117.3 ms, skewness      0.1 ms
  steady state:  n =  64, mean    603.9 ms, stddev     83.3 ms, skewness     -0.1 ms
```
