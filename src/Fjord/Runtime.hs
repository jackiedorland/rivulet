{-# LANGUAGE OverloadedStrings #-}
module Fjord.Runtime where

import Fjord.Types
import Fjord.Log

import Control.Concurrent.STM
import Control.Monad (forever)
import Data.IORef
import qualified Data.Map as Map

loop :: Runtime -> IO ()
loop rt = forever $ do
  ev <- atomically $
      readTQueue (events rt)
  
  handle rt ev

handle :: Runtime -> Event -> IO ()
handle rt e = case e of
  RiverUnavailable -> do 
    atomically $ writeTQueue (logs rt) $ Fatal "river_window_management_v1 Wayland protocol unavailable. Is another layout engine running?"
  RiverFinished -> do
    warn rt "RiverFinished received from server! Beginning graceful exit."
    dts <- readIORef (destructors rt)
    mapM_ (\(Destructor d) -> d) (Map.elems dts)
    fatal rt "Session finished."
  RiverLocked -> modifyIORef' (state rt) $ \s -> s { locked = True }
  RiverUnlocked -> modifyIORef' (state rt) $ \s -> s { locked = False }
  WinCreated wid -> modifyIORef' (state rt) $ \s -> s { windows = Map.insert wid (defaultWindow wid) (windows s) }
  OutputCreated oid -> pure ()
  SeatCreated sid -> pure ()
  WinClosed wid -> pure ()
  WinDimensionsHint wid minW minH maxW maxH -> pure ()
  WinDimensions wid w h -> pure ()
  WinSetAppId wid appId -> pure ()
  WinSetTitle wid title -> pure ()
  WinSetParent wid parent -> pure ()
  WinDecorationHint wid hint -> pure ()
  WinPtrMoveReq wid sid -> pure ()
  WinPtrResizeReq wid sid edges -> pure ()
  WinShowDecorationMenu wid x y -> pure ()
  WinMaximizeReq wid -> pure ()
  WinUnmaximizeReq wid -> pure ()
  WinFullscreenReq wid output -> pure ()
  WinExitFullscreenReq wid -> pure ()
  WinMinimizeReq wid -> pure ()
  WinUnreliablePID wid pid -> pure ()
  OutRemoved oid -> pure ()
  OutWlName oid name -> pure ()
  OutPosition oid x y -> pure ()
  OutDimensions oid w h -> pure ()
  SeatRemoved sid -> pure ()
  SeatWlName sid name -> pure ()
  SeatPtrEnter sid wid -> pure ()
  SeatPtrLeave sid -> pure ()
  SeatWinInteraction sid wid -> pure ()
  SeatShellInteraction sid shid -> pure ()
  SeatOpDelta sid dx dy -> pure ()
  SeatOpRelease sid -> pure ()
  SeatPtrPos sid x y -> pure ()
