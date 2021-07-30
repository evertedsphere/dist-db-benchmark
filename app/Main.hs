{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

import Control.Concurrent ()
import Control.Concurrent.Async (forConcurrently)
import Control.Monad (forM, forM_, replicateM_, void)
import Control.Monad.IO.Class ( MonadIO(..) )
import Control.Monad.Reader
  ( MonadReader,
    ReaderT (runReaderT),
    asks,
  )
import Data.Aeson (ToJSON (toJSON), Value)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.String (IsString (..))
import Data.UUID (UUID)
import Data.UUID.V4 as UUID (nextRandom)
import Data.Vector (Vector)
import Data.Vector qualified as Vector
import Database.PostgreSQL.Simple
  ( Connection,
    FromRow,
    Only (Only),
    Query,
    ToRow,
    connectPostgreSQL,
    execute,
    execute_,
    query,
    query_,
  )
import GHC.Generics (Generic)
import Statistics.Sample qualified as Statistics
import System.Clock
  ( Clock (Monotonic),
    diffTimeSpec,
    getTime,
    toNanoSecs,
  )
import System.Environment (getArgs, getEnv)
import System.IO (hFlush, stdout)
import Text.Printf (printf)

data MetadataQuery
  = MetadataSelect
  | MetadataUpdate Value UUID

updateMetadata ::
  (MonadIO m, MonadReader Env m) => Query -> Query -> String -> Int -> m ()
updateMetadata select update testName numThreads = do
  connString <- asks envConnString
  numRuns <- asks envNumRuns
  let fullTestName =
        testName
          <> " ("
          <> show numThreads
          <> " thr × "
          <> show numRuns
          <> " runs each)"
  liftIO $ putStrLn $ "\nrunning test:h " <> fullTestName
  conn <- measureTime 0 "acquiring conn" $ liftIO $ connectPostgreSQL connString
  allIds :: [Only UUID] <-
    measureTime 0 "select ids" (liftIO $ query conn select (Only (numRuns * numThreads)))

  (firsts :: [Double], rests :: [Vector Double]) <-
    liftIO $
      unzip <$> forConcurrently [1 .. numThreads] \tid -> do
        -- putStrLn $ "in thread " ++ show tid
        conn <- measureTime tid "acquiring conn" $ connectPostgreSQL connString
        let ids = take numRuns (drop ((tid - 1) * numRuns) allIds) -- lmao
        times <-
          Vector.fromList <$> forM ids \(Only i) -> do
            -- print i
            meta <- toJSON <$> mkMetadata
            ((), t) <- measureTime_ tid "update" do
              runSql (Proxy @(Only Value)) (MetadataUpdate meta i) conn update
            pure t
        pure (Vector.head times, Vector.tail times)

  -- putStrLn fullTestName
  liftIO $ printf "  first runs: "
  ppStats (Vector.fromList firsts)
  liftIO $ printf "  later runs: "
  ppStats (mconcat rests)

updateMetadataGlobal =
  updateMetadata
    "SELECT project_id FROM hdb_metadata LIMIT ?"
    "UPDATE hdb_metadata SET metadata = ? WHERE project_id = ?"
    "update, one row, non-partitioned"

updateMetadataLocal =
  updateMetadata
    "SELECT project_id FROM hdb_metadata_split WHERE geo_partition = 'IN' LIMIT ?"
    "UPDATE hdb_metadata_split SET metadata = ? WHERE project_id = ? AND geo_partition = 'IN'"
    "update, one row, partitioned"

getConnString :: IO ByteString
getConnString = fromString <$> getEnv "METADATA_BENCHMARK_CONN_STRING"

getNumRuns :: IO Int
getNumRuns = read <$> getEnv "METADATA_BENCHMARK_NUM_RUNS"

data Env = Env {envConnString :: ByteString, envNumRuns :: Int}
  deriving (Show)

main = do
  connString <- getConnString
  numRuns <- getNumRuns
  putStrLn ("conn string: " ++ show connString)
  let env = Env connString numRuns
  flip runReaderT env do
    -- this can be eta-reduced into for xs (for ys) but that looks odd
    forM_ [updateMetadataGlobal, updateMetadataLocal] \bench -> do
      forM_ [1, 2, 5, 10] \numThreads -> do
        bench numThreads

-- putStrLn "\nrunning test: 2 × 10 select 1"
-- measureTime threadNum "2 × 10 select 1" do
--   h <- async do
--     conn <- measureTime threadNum "acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 1: select 1" do
--         runSqlFile (Proxy @(Only Int)) NoArgs conn "select1.sql"
--   h' <- async do
--     conn <- measureTime threadNum "acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 2: select 1" do
--         runSqlFile (Proxy @(Only Int)) NoArgs conn "select1.sql"
--   wait h
--   wait h'

-- putStrLn "\nrunning test: 2 × 10 select metadata non-partitioned"
-- measureTime threadNum "2 × 10 select metadata non-partitioned" do
--   h <- async do
--     conn <- measureTime threadNum "thread 1: acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 1: select metadata non-partitioned" do
--         runSqlFile (Proxy @(Only Value)) NoArgs conn "select_metadata.sql"
--   h' <- async do
--     conn <- measureTime threadNum "thread 2: acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 2: select metadata non-partitioned" do
--         runSqlFile (Proxy @(Only Value)) NoArgs conn "select_metadata.sql"
--   wait h
--   wait h'

-- putStrLn "\nrunning test: 2 × 10 select metadata partitioned local"
-- measureTime threadNum "2 × 10 select metadata partitioned local" do
--   h <- async do
--     conn <- measureTime threadNum "thread 1: acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 1: select metadata partitioned local" do
--         runSqlFile (Proxy @(Only Value)) NoArgs conn "select_metadata_local.sql"
--   h' <- async do
--     conn <- measureTime threadNum "thread 2: acquiring conn" $ connectPostgreSQL connString
--     replicateM_ 10 do
--       measureTime threadNum "thread 2: select metadata partitioned local" do
--         runSqlFile (Proxy @(Only Value)) NoArgs conn "select_metadata_local.sql"
--   wait h

--   wait h'

--------------------------------------------------------------------------------
-- utils
--------------------------------------------------------------------------------

trunc :: Double -> Int -> Double
trunc x n = fromIntegral (floor (x * t)) / t
  where
    t = 10 ^ n

data FakeMetadata = FakeMetadata {foo :: UUID, bar :: UUID}
  deriving (Generic)

instance ToJSON FakeMetadata

mkMetadata :: IO FakeMetadata
mkMetadata = FakeMetadata <$> UUID.nextRandom <*> UUID.nextRandom

runSqlFile ::
  forall r a. FromRow r => Proxy r -> MetadataQuery -> Connection -> FilePath -> IO ()
runSqlFile p payload conn f = void do
  q <- fromString <$> readFile f
  runSql p payload conn q

runSql ::
  forall r a. FromRow r => Proxy r -> MetadataQuery -> Connection -> Query -> IO ()
runSql _ payload conn q = void do
  case payload of
    MetadataSelect -> void $ query_ @r conn q
    MetadataUpdate a b -> void $ execute conn q (a, b)
  pure ()

threadPrefix threadNum = "T#" ++ show threadNum ++ " "

measureTime_ :: MonadIO m => Int -> [Char] -> m a -> m (a, Double)
measureTime_ threadNum msg f = do
  start <- liftIO $ getTime Monotonic
  r <- f
  end <- liftIO $ getTime Monotonic
  let delta = fromInteger (toNanoSecs (diffTimeSpec end start)) / 1_000_000.0
  -- putStrLn
  --   ( threadPrefix threadNum ++ msg
  --       ++ " -> "
  --       ++ show (trunc delta 1)
  --       ++ " ms"
  --   )
  pure (r, delta)

measureTime :: MonadIO m => Int -> [Char] -> m a -> m a
measureTime t m f = fst <$> measureTime_ t m f

-- replicateQuery connString n tid f = do
--   conn <- measureTime tid "acquiring conn" $ connectPostgreSQL connString
--   replicateM_ n (f tid conn)

--------------------------------------------------------------------------------
-- stats
--------------------------------------------------------------------------------

data Stats = Stats
  { statsCount :: Int,
    statsMean :: Double,
    statsStdDev :: Double,
    statsSkewness :: Double
  }

computeStats :: Vector Double -> Stats
computeStats xs = Stats count mean std skew
  where
    count = Vector.length xs
    [mean, std, skew] =
      map
        (\f -> trunc (f xs) 1)
        [ Statistics.mean,
          Statistics.stdDev,
          Statistics.skewness
        ]

ppStats :: MonadIO m => Vector Double -> m ()
ppStats xs =
  let Stats {..} = computeStats xs
   in liftIO $
        printf
          "count %3d, mean %8.1f ms, stddev %8.1f ms, skewness %8.1f ms\n"
          statsCount
          statsMean
          statsStdDev
          statsSkewness
