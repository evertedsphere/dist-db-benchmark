{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

import Control.Concurrent ()
import Control.Concurrent.Async (forConcurrently)
import Control.Monad (forM, forM_, replicateM_, void)
import Data.Aeson (ToJSON (toJSON), Value)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Kind (Type)
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
import Formatting ()
import Formatting.Clock ()
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

data Proxy (r :: Type) = Proxy

data FakeMetadata = FakeMetadata {foo :: UUID, bar :: UUID}
  deriving (Generic)
instance ToJSON FakeMetadata
mkMetadata :: IO FakeMetadata
mkMetadata = FakeMetadata <$> UUID.nextRandom <*> UUID.nextRandom

runSqlFile :: forall r a. FromRow r => Proxy r -> QueryPayload -> Connection -> FilePath -> IO ()
runSqlFile p payload conn f = void do
  q <- fromString <$> readFile f
  runSql p payload conn q

runSql :: forall r a. FromRow r => Proxy r -> QueryPayload -> Connection -> Query -> IO ()
runSql _ payload conn q = void do
  case payload of
    NoArgs -> void $ query_ @r conn q
    MetadataUpdate a b -> void $ execute conn q (a, b)
  pure ()

threadPrefix threadNum = "T#" ++ show threadNum ++ " "

measureTime_ :: Int -> [Char] -> IO a -> IO (a, Double)
measureTime_ threadNum msg f = do
  start <- getTime Monotonic
  r <- f
  end <- getTime Monotonic
  let delta = fromInteger (toNanoSecs (diffTimeSpec end start)) / 1_000_000.0
  -- putStrLn
  --   ( threadPrefix threadNum ++ msg
  --       ++ " -> "
  --       ++ show (truncate' delta 1)
  --       ++ " ms"
  --   )
  hFlush stdout
  pure (r, delta)

data QueryPayload 
  = NoArgs 
  | MetadataUpdate Value UUID

measureTime :: Int -> [Char] -> IO b -> IO b
measureTime t m f = fst <$> measureTime_ t m f

updateMetadata :: Query -> Query -> String -> Int -> Int -> ByteString -> IO ()
updateMetadata select update testName numRuns numThreads connString = do
  let fullTestName =
        testName
          <> " ("
          <> show numThreads
          <> " thr × "
          <> show numRuns
          <> " runs each)"
  putStrLn $ "\nrunning test: " <> fullTestName
  conn <- measureTime 0 "acquiring conn" $ connectPostgreSQL connString
  allIds :: [Only UUID] <-
    measureTime 0 "select ids" (query conn select (Only (numRuns * numThreads)))

  let allStats :: Vector Double -> (Int, Double, Double)
      allStats xs = (count, mean, std)
        where
          count = Vector.length xs
          mean = truncate' (Statistics.mean xs) 1
          std = truncate' (Statistics.stdDev xs) 1

  (firsts :: [Double], rests :: [Vector Double]) <-
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

  let (fn, fm, fs) = allStats (Vector.fromList firsts)
      (rn, rm, rs) = allStats (mconcat rests)

  -- putStrLn fullTestName
  printf "  first runs: count %3d, mean %8.1f ms, stddev %8.1f ms\n" fn fm fs
  printf "  later runs: count %3d, mean %8.1f ms, stddev %8.1f ms\n" rn rm rs

updateMetadataGlobal :: Int -> Int -> ByteString -> IO ()
updateMetadataGlobal =
  updateMetadata
    "SELECT project_id FROM hdb_metadata LIMIT ?"
    "UPDATE hdb_metadata SET metadata = ? WHERE project_id = ?"
    "update metadata, non-partitioned"

updateMetadataLocal :: Int -> Int -> ByteString -> IO ()
updateMetadataLocal =
  updateMetadata
    "SELECT project_id FROM hdb_metadata_split WHERE geo_partition = 'IN' LIMIT ?"
    "UPDATE hdb_metadata_split SET metadata = ? WHERE project_id = ? AND geo_partition = 'IN'"
    "update metadata, partitioned"

data Env = Env {connectionString :: ByteString, numRuns :: Int}
  deriving (Show)

main = do
  connString <- getConnString
  putStrLn ("conn string: " ++ show connString)
  updateMetadataGlobal 10 1 connString
  updateMetadataGlobal 10 2 connString
  updateMetadataGlobal 10 5 connString
  updateMetadataGlobal 10 15 connString
  updateMetadataLocal 10 1 connString
  updateMetadataLocal 10 2 connString
  updateMetadataLocal 10 5 connString
  updateMetadataLocal 10 15 connString

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

-- utils

getConnString :: IO ByteString
getConnString = fromString <$> getEnv "METADATA_BENCHMARK_CONN_STRING"

truncate' :: Double -> Int -> Double
truncate' x n = fromIntegral (floor (x * t)) / t
  where
    t = 10 ^ n

-- replicateQuery connString n tid f = do
--   conn <- measureTime tid "acquiring conn" $ connectPostgreSQL connString
--   replicateM_ n (f tid conn)
