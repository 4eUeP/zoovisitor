{-# LANGUAGE CApiFFI          #-}
{-# LANGUAGE CPP              #-}
{-# LANGUAGE UnliftedFFITypes #-}

module ZooKeeper.Internal.FFI where

import           Control.Concurrent
import           Control.Exception
import           Control.Monad                (void)
import           Data.Version                 (Version, makeVersion)
import           Data.Word
import           Foreign.C
import           Foreign.ForeignPtr
import           Foreign.Ptr
import           Foreign.StablePtr
import           GHC.Conc
import           GHC.Stack                    (HasCallStack)
import qualified Z.Data.CBytes                as CBytes
import           Z.Foreign

import           ZooKeeper.Exception
import           ZooKeeper.Internal.Types

#include "hs_zk.h"

#ifndef ZOO_MAJOR_VERSION
import           Data.Version                 (parseVersion)
import           Text.ParserCombinators.ReadP (readP_to_S)
#endif

-------------------------------------------------------------------------------

zooVersion :: Version
#ifdef ZOO_MAJOR_VERSION
-- For zookeeper-3.4
zooVersion = makeVersion [ (#const ZOO_MAJOR_VERSION)
                         , (#const ZOO_MINOR_VERSION)
                         , (#const ZOO_PATCH_VERSION)
                         ]
#else
-- For zookeeper-3.6+
zooVersion = case readP_to_S parseVersion (#const_str ZOO_VERSION) of
               [_, _, (r, _)] -> r
               _otherwise     -> makeVersion [0, 0, 0]  -- unsupported
#endif

foreign import ccall unsafe "hs_zk.h &logLevel"
  c_log_level :: Ptr ZooLogLevel

-- | Sets the debugging level for the zookeeper library
foreign import ccall unsafe "hs_zk.h zoo_set_debug_level"
  zooSetDebugLevel :: ZooLogLevel -> IO ()

foreign import capi unsafe "zookeeper/zookeeper.h zoo_set_log_stream"
  c_zoo_set_log_stream :: Ptr CFile -> IO ()

foreign import ccall unsafe "hs_zoo_set_std_log_stream"
  hs_zoo_set_std_log_stream :: CInt -> IO ()

foreign import ccall "wrapper"
  mkCWatcherFnPtr :: CWatcherFn -> IO (FunPtr CWatcherFn)

mkWatcherFnPtr :: WatcherFn -> IO (FunPtr CWatcherFn)
mkWatcherFnPtr fn = mkCWatcherFnPtr $ \zh ev st cpath _ctx -> do
  path <- CBytes.fromCString cpath
  -- FIXME: better way
  --
  -- Here we fork a new thread to run the user's watcher function to avoid
  -- blocking the C thread, potential deadlock.
  --
  -- Without forkIO, the following code will deadlock,
  --
  -- @
  -- gloWatcher :: WatcherFn
  -- gloWatcher zh event state path = do
  --   print =<< zooGet zh "/node"
  --
  -- zookeeperResInit "127.0.0.1:2181" (Just gloWatcher) 5000 Nothing 0
  -- ...
  -- @
  --
  -- The reason is:
  --
  --   * All zookeeper completions are run by one completion c thread (or
  --     likely in one thread).
  --   * We are blocking on a MVar and waiting for the callback of zoo_aget
  --     return.
  --   * gloWatcher will be called by zookeeper library as a c function, which
  --     means any blocking in haskell code will block the c thread.
  --
  -- So, zooGet is waiting for the result of zoo_aget, and blocking on an MVar,
  -- which will block the completion c thread here. The result of zoo_aget is
  -- returned by this completion c thread, so it will never be called.
  void $ forkIO $ fn zh (ZooEvent ev) (ZooState st) path

foreign import ccall safe "zookeeper.h zookeeper_init"
  zookeeper_init
    :: Ptr Word8
    -> FunPtr CWatcherFn
    -> CInt
    -> ClientID
    -> Ptr a
    -> CInt
    -> IO ZHandle

foreign import ccall safe "hs_zk.h zookeeper_close"
  c_zookeeper_close :: ZHandle -> IO CInt

foreign import ccall unsafe "hs_zk.h zoo_client_id"
  c_zoo_client_id :: ZHandle -> IO ClientID

foreign import ccall unsafe "hs_zk.h zoo_state"
  c_zoo_state :: ZHandle -> IO ZooState

foreign import ccall unsafe "hs_zk.h zoo_recv_timeout"
  c_zoo_recv_timeout :: ZHandle -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aget_acl"
  c_hs_zoo_aget_acl
    :: ZHandle -> BA## Word8
    -> StablePtr PrimMVar -> Int -> Ptr AclCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_acreate"
  c_hs_zoo_acreate
    :: ZHandle
    -> BA## Word8
    -> BA## Word8 -> Int -> Int
    -> AclVector
    -> CreateMode
    -> StablePtr PrimMVar -> Int -> Ptr StringCompletion
    -> IO CInt
foreign import ccall unsafe "hs_zk.h hs_zoo_acreate"
  c_hs_zoo_acreate'
    :: ZHandle
    -> BA## Word8
    -> Ptr CChar -> Int -> Int
    -> AclVector
    -> CreateMode
    -> StablePtr PrimMVar -> Int -> Ptr StringCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aset"
  c_hs_zoo_aset
    :: ZHandle
    -> BA## Word8
    -> BA## Word8 -> Int -> Int
    -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr StatCompletion
    -> IO CInt
foreign import ccall unsafe "hs_zk.h hs_zoo_aset"
  c_hs_zoo_aset'
    :: ZHandle
    -> BA## Word8
    -> Ptr Word8 -> Int -> Int
    -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr StatCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aget"
  c_hs_zoo_aget
    :: ZHandle
    -> BA## Word8
    -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr DataCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_awget"
  c_hs_zoo_awget
    :: ZHandle -> BA## Word8
    -> StablePtr PrimMVar -> StablePtr PrimMVar -> Int
    -> Ptr HsWatcherCtx -> Ptr DataCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_adelete"
  c_hs_zoo_adelete
    :: ZHandle
    -> BA## Word8 -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr VoidCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aexists"
  c_hs_zoo_aexists
    :: ZHandle -> BA## Word8 -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr StatCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_awexists"
  c_hs_zoo_awexists
    :: ZHandle -> BA## Word8
    -> StablePtr PrimMVar -> StablePtr PrimMVar -> Int
    -> Ptr HsWatcherCtx -> Ptr StatCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aget_children"
  c_hs_zoo_aget_children
    :: ZHandle -> BA## Word8 -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr StringsCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_awget_children"
  c_hs_zoo_awget_children
    :: ZHandle -> BA## Word8
    -> StablePtr PrimMVar -> StablePtr PrimMVar -> Int
    -> Ptr HsWatcherCtx -> Ptr StringsCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_aget_children2"
  c_hs_zoo_aget_children2
    :: ZHandle -> BA## Word8 -> CInt
    -> StablePtr PrimMVar -> Int -> Ptr StringsStatCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_awget_children2"
  c_hs_zoo_awget_children2
    :: ZHandle -> BA## Word8
    -> StablePtr PrimMVar -> StablePtr PrimMVar -> Int
    -> Ptr HsWatcherCtx -> Ptr StringsStatCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_amulti"
  c_hs_zoo_amulti
    :: ZHandle -> CInt
    -> MBA## CZooOp           -- Ptr CZooOp
    -> MBA## CZooOpResult     -- Ptr CZooOpResult
    -> StablePtr PrimMVar -> Int -> Ptr VoidCompletion
    -> IO CInt

foreign import ccall unsafe "hs_zk.h hs_zoo_create_op_init"
  c_hs_zoo_create_op_init
    :: Ptr CZooOp
    -> BA## Word8           -- ^ path
    -> BA## Word8 -> Int -> Int
    -> AclVector
    -> CreateMode
    -> MBA## Word8 -> CInt   -- ^ (path_buffer, path_buffer_len)
    -> IO ()
foreign import ccall unsafe "hs_zk.h hs_zoo_create_op_init"
  c_hs_zoo_create_op_init'
    :: Ptr CZooOp
    -> BA## Word8
    -> Ptr CChar -> Int -> Int
    -> AclVector
    -> CreateMode
    -> MBA## Word8 -> CInt
    -> IO ()

foreign import ccall unsafe "hs_zk.h zoo_delete_op_init"
  c_zoo_delete_op_init :: Ptr CZooOp -> BA## Word8 -> CInt -> IO ()

foreign import ccall unsafe "hs_zk.h hs_zoo_set_op_init"
  c_hs_zoo_set_op_init
    :: Ptr CZooOp
    -> BA## Word8
    -> BA## Word8 -> Int -> Int
    -> CInt
    -> MBA## Word8     -- pointer to Stat
    -> IO ()
foreign import ccall unsafe "hs_zk.h hs_zoo_set_op_init"
  c_hs_zoo_set_op_init'
    :: Ptr CZooOp
    -> BA## Word8
    -> Ptr Word8 -> Int -> Int
    -> CInt
    -> MBA## Word8     -- pointer to Stat
    -> IO ()

foreign import ccall safe "zookeeper.h zoo_set_watcher"
  zoo_set_watcher :: ZHandle -> FunPtr CWatcherFn -> IO (FunPtr CWatcherFn)

foreign import ccall unsafe "zookeeper.h zoo_check_op_init"
  c_zoo_check_op_init :: Ptr CZooOp -> BA## Word8 -> CInt -> IO ()

foreign import ccall unsafe "zookeeper.h is_unrecoverable"
  c_is_unrecoverable :: ZHandle -> IO CInt

-------------------------------------------------------------------------------

foreign import capi unsafe "stdio.h fopen"
  c_fopen :: BA## Word8 -> BA## Word8 -> IO (Ptr CFile)

foreign import capi unsafe "stdio.h fclose"
  c_fclose :: Ptr CFile -> IO CInt

foreign import capi unsafe "stdio.h fflush"
  c_fflush :: Ptr CFile -> IO CInt

-------------------------------------------------------------------------------
-- Helpers

withZKAsync :: HasCallStack
            => Int -> (Ptr a -> IO CInt) -> (Ptr a -> IO a)
            -> (StablePtr PrimMVar -> Int -> Ptr a -> IO CInt)
            -> IO (Either CInt a)
withZKAsync = withZKAsync' []
{-# INLINE withZKAsync #-}

withZKAsync' :: HasCallStack
             => TouchListBytes
             -> Int -> (Ptr a -> IO CInt) -> (Ptr a -> IO a)
             -> (StablePtr PrimMVar -> Int -> Ptr a -> IO CInt)
             -> IO (Either CInt a)
withZKAsync' bas size peek_result peek_data f = mask_ $ do
  mvar <- newEmptyMVar
  sp <- newStablePtrPrimMVar mvar
  fp <- mallocForeignPtrBytes size
  withForeignPtr fp $ \data' -> do
    (cap, _) <- threadCapability =<< myThreadId
    void $ throwZooErrorIfNotOK =<< f sp cap data'
    takeMVar mvar `onException` forkIO (do takeMVar mvar; touchForeignPtr fp; touch bas)
    rc <- peek_result data'
    case rc of
      CZOK -> Right <$> peek_data data'
      _    -> return $ Left rc
{-# INLINE withZKAsync' #-}

withZKAsync2
  :: HasCallStack
  => Int -> (Ptr a -> IO CInt) -> (Ptr a -> IO a)
  -> (Either CInt a -> IO ())
  -> Int -> (Ptr b -> IO CInt) -> (Ptr b -> IO b)
  -> (Either CInt b -> IO ())
  -> (StablePtr PrimMVar -> StablePtr PrimMVar -> Int -> Ptr a -> Ptr b -> IO CInt)
  -> IO ()
withZKAsync2 size1 peekRet1 peekData1 f1 size2 peekRet2 peekData2 f2 g = mask_ $ do
  mvar1 <- newEmptyMVar
  sp1 <- newStablePtrPrimMVar mvar1
  fp1 <- mallocForeignPtrBytes size1

  mvar2 <- newEmptyMVar
  sp2 <- newStablePtrPrimMVar mvar2
  fp2 <- mallocForeignPtrBytes size2

  withForeignPtr fp1 $ \data1' ->
    withForeignPtr fp2 $ \data2' -> do
      (cap, _) <- threadCapability =<< myThreadId
      void $ throwZooErrorIfNotOK =<< g sp1 sp2 cap data1' data2'

      takeMVar mvar2 `onException` forkIO (do takeMVar mvar2; touchForeignPtr fp2; touchForeignPtr fp1)
      rc2 <- peekRet2 data2'
      case rc2 of
        CZOK -> f2 =<< Right <$> peekData2 data2'
        _    -> f2 $ Left rc2

      takeMVar mvar1 `onException` forkIO (do takeMVar mvar1; touchForeignPtr fp1)
      rc1 <- peekRet1 data1'
      case rc1 of
        CZOK -> f1 =<< Right <$> peekData1 data1'
        _    -> f1 $ Left rc1
{-# INLINABLE withZKAsync2 #-}
