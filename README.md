benchmark for (distributed) databases that speak the postgres wire protocol.

```
# install cabal and ghc first, via ghcup or your system package manager

export METADATA_BENCHMARK_CONN_STRING=<pg conn string>

psql METADATA_BENCHMARK_CONN_STRING -f init.sql

cabal new-run
```
