{- HLINT ignore "Redundant pure" -}
{-# LANGUAGE BlockArguments #-}
module Rivulet.Manager where

import           Rivulet.DSL            (Config (..))
import           Rivulet.DSL.Layout     (Tall (..))
import           Rivulet.FFI.Protocol
import           Rivulet.Types

import           Control.Concurrent.STM (readTVarIO)
import           Control.Exception      (finally)
import           Control.Monad          (when, unless)
import qualified Data.Map               as Map
import           Data.Maybe
import qualified Data.Set               as Set
import           Foreign
import           Rivulet.Manager.Log    (Logger, logEvent)
import           Rivulet.Monad
import           UnliftIO.Async         (forConcurrently, forConcurrently_)

marginsFromConfig :: Config -> Margins
marginsFromConfig config =
  let gap = fromMaybe 0 (cfgGaps config)
      bw = maybe 0 (borderWidth . fst) (cfgBorders config)
   in Margins gap bw

proposeForMonitor :: Logger -> Config -> WMState -> MonitorId -> IO Prearrangement
proposeForMonitor logger config state monId =
  case Map.lookup monId (monitors state) of
    Nothing -> pure []
    Just mon ->
      case Map.lookup (activeSpace mon) (workspaces state) of
        Nothing -> pure []
        Just ws -> do
          let winIds   = wsWindows ws
              layout   = case layouts ws of { (l:_) -> l; [] -> SomeLayout Tall }
              proposals = propose layout mon (marginsFromConfig config) winIds
              wcount   = length proposals
          logEvent logger "propose"
            $ show monId <> " -> " <> show wcount <> " window" <> if wcount == 1 then "" else "s"
          -- only send dimensions to River if they actually changed
          -- (terminals snap to character grid so winGeometry never matches exactly)
          forConcurrently_ proposals $ \(winId, dims) -> do
            logEvent logger "propose"
              $ show winId <> " dimensions=" <> show (width dims) <> "×" <> show (height dims)
            case Map.lookup winId (windows state) of
              Nothing -> pure ()
              Just win ->
                when (winProposed win /= Just (width dims, height dims))
                  $ riverWindowV1ProposeDimensions (rawWindow win) (width dims) (height dims)
          pure proposals

positionForMonitor :: Config -> WMState -> Monitor -> IO [(WindowId, Rect)]
positionForMonitor config state mon =
  case Map.lookup (activeSpace mon) (workspaces state) of
    Nothing -> pure []
    Just ws -> do
      let winIds    = wsWindows ws
          dims      = mapMaybe
            (\wId -> fmap (\w -> (wId, (width (winGeometry w), height (winGeometry w))))
                          (Map.lookup wId (windows state)))
            winIds
          layout    = case layouts ws of { (l:_) -> l; [] -> SomeLayout Tall }
          positions = arrange layout mon (marginsFromConfig config) dims
      forConcurrently positions $ \(winId, rect) ->
        case Map.lookup winId (windows state) of
          Nothing  -> pure (winId, rect)
          Just win ->
            case rawNode win of
              Nothing   -> pure (winId, rect)
              Just node -> do
                when (lastPosition win /= Just (x rect, y rect))
                  $ riverNodeV1SetPosition node (x rect) (y rect)
                pure (winId, rect)

setBorderForWindow :: WMState -> (Border, Border) -> (WindowId, Window) -> IO ()
setBorderForWindow state (focusedBorder, normalBorder) (winId, win) =
  unless (fst (fullscreen win)) do
    let focused        = any (\s -> keyboardFocus s == Just winId) (Map.elems (seats state))
        Border _ w col = if focused then focusedBorder else normalBorder
    riverWindowV1SetBorders (rawWindow win) 0xF w col

onWmManageStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmManageStart runtime config wmPtr = do
  let logger  = rtLogger runtime
      wmState = rtState runtime
  -- snapshot state once at the top; safe because the event loop is single-threaded
  state <- readTVarIO wmState
  let seatList   = Map.toList $ seats state
      windowList = Map.toList $ windows state
  -- ManageFinish is guaranteed to fire even if something throws
  finally
    (do
       forConcurrently_ seatList $ \(seatId, seatVal) ->
         forConcurrently_ (pendingBindings seatVal) $ \(ptr, _) ->
           riverXkbBindingV1Enable ptr

       -- only call riverSeatV1FocusWindow if focus actually changed since last time
       newFoci <- forConcurrently seatList $ \(seatId, seatVal) -> do
         let current = keyboardFocus seatVal
             lastSent = lastSentFocus seatVal
         when (current /= lastSent) do
           logEvent logger "focus" $ "seat " <> show seatId <> " -> " <> show current
           case current of
             Nothing    -> riverSeatV1ClearFocus (rawSeat seatVal)
             Just winId ->
               case Map.lookup winId (windows state) of
                 Nothing  -> pure ()
                 Just win -> riverSeatV1FocusWindow (rawSeat seatVal) (rawWindow win)
         pure (seatId, current)

       -- for any window requesting fullscreen, resolve which monitor to use:
       -- if a specific monitor was requested use that, otherwise use the window's current monitor
       forConcurrently_ windowList $ \(_, win) ->
         when (fst (fullscreen win)) do
           let monId = case snd (fullscreen win) of
                 Nothing -> let WorkspaceId (mId, _) = winWorkspace win in mId
                 Just mId -> mId
           case Map.lookup monId (monitors state) of
             Nothing  -> pure ()
             Just mon -> riverWindowV1Fullscreen (rawWindow win) (rawOutput mon)

       proposals <-
         fmap concat
           $ forConcurrently (Set.toList (dirtyMonitors state))
           $ proposeForMonitor logger config state

       updateState wmState $ \s ->
         s { dirtyMonitors = Set.empty
           , seats = foldr
               (\(seatId, newFocus) acc -> Map.adjust
                 (\seat -> seat
                   { lastSentFocus  = newFocus
                   , seatBindings   = seatBindings seat ++ pendingBindings seat
                   , pendingBindings = []
                   })
                 seatId acc)
               (seats s) newFoci
           , windows = foldr
               (\(winId, dims) acc -> Map.adjust
                 (\win -> win { winProposed = Just (width dims, height dims) })
                 winId acc)
               (windows s) proposals
           })
    (do
       -- logEvent logger "manageFinish" "done"
       riverWindowManagerV1ManageFinish wmPtr)

onWmRenderStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmRenderStart runtime config wmPtr = do
  let logger  = rtLogger runtime
      wmState = rtState runtime
  state <- readTVarIO wmState
  -- RenderFinish is guaranteed to fire even if something throws
  finally
    (do
       -- render ALL monitors every sequence (not just dirty ones)
       -- render sequences can fire without a preceding manage sequence
       -- e.g. a window independently changes its own dimensions
       allPositions <-
         fmap concat
           $ forConcurrently (Map.elems (monitors state))
           $ positionForMonitor config state

       case cfgBorders config of
         Nothing      -> pure ()
         Just borders ->
           forConcurrently_ (Map.toList (windows state))
             $ setBorderForWindow state borders

       updateState wmState $ \s ->
         s { windows = foldr
               (\(winId, rect) acc -> Map.adjust
                 (\win -> win { lastPosition = Just (x rect, y rect) })
                 winId acc)
               (windows s) allPositions
           })
    (do
       -- logEvent logger "renderFinish" "done"
       riverWindowManagerV1RenderFinish wmPtr)
