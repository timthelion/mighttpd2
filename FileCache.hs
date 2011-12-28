{-# LANGUAGE BangPatterns #-}

module FileCache (fileCacheInit) where

import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.ByteString (ByteString)
import Data.HashMap (Map)
import qualified Data.HashMap as M
import Data.IORef
import Network.HTTP.Date
import Network.Wai.Application.Classic
import System.IO.Unsafe
import System.Posix.Files

data Entry = Negative | Positive FileInfo
type Cache = Map ByteString Entry
type GetInfo = Path -> IO FileInfo

fileInfo :: IORef Cache -> GetInfo
fileInfo ref path = do
  !mx <- atomicModifyIORef ref (lok path)
  case mx of
      Nothing -> throwIO (userError "fileInfo")
      Just x  -> return x

lok :: Path -> Cache -> (Cache, Maybe FileInfo)
lok path cache = unsafePerformIO $ do
    let ment = M.lookup bpath cache
    case ment of
        Nothing -> handle handler $ do
            let sfile = pathString path
            fs <- getFileStatus sfile
            if doesExist fs then pos fs else neg
        Just Negative     -> return (cache, Nothing)
        Just (Positive x) -> return (cache, Just x)
  where
    size = fromIntegral . fileSize
    mtime = epochTimeToHTTPDate . modificationTime
    doesExist = not . isDirectory
    bpath = pathByteString path
    pos fs = do
        let info = FileInfo {
                fileInfoName = path
              , fileInfoSize = size fs
              , fileInfoTime = mtime fs
              }
            entry = Positive info
            cache' = M.insert bpath entry cache
        return (cache', Just info)
    neg = do
        let cache' = M.insert bpath Negative cache
        return (cache', Nothing)
    handler :: SomeException -> IO (Cache, Maybe FileInfo)
    handler _ = neg

fileCacheInit :: IO GetInfo
fileCacheInit = do
    ref <- newIORef M.empty
    forkIO (remover ref)
    return $ fileInfo ref

-- atomicModifyIORef is not necessary here.
remover :: IORef Cache -> IO ()
remover ref = forever $ threadDelay 10000000 >> writeIORef ref M.empty
