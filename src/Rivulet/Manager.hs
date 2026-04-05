{- HLINT ignore "Redundant pure" -}
module Rivulet.Manager where

import           Rivulet.DSL            (Config (..))
import           Rivulet.DSL.Layout     (Tall (..))
import           Rivulet.FFI.Protocol
import           Rivulet.Types

import           Control.Concurrent.STM (readTVarIO)
import           Control.Exception      (finally)
import           Control.Monad          (when)
import qualified Data.Map               as Map
import           Data.Maybe
import qualified Data.Set               as Set
import           Foreign
import           GHC.Clock              (getMonotonicTime)
import           Rivulet.Manager.Log    (logEvent)
import           Rivulet.Monad
import           Text.Printf            (printf)
import           UnliftIO.Async         (forConcurrently, forConcurrently_)

marginsFromConfig :: Config -> Margins
marginsFromConfig config =
  let gap = fromMaybe 0 (cfgGaps config)
      bw = maybe 0 (borderWidth . fst) (cfgBorders config)
   in Margins gap bw

onWmManageStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmManageStart runtime config wmPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
    -- snapshot state once at the top; safe because the event loop is single-threaded
  state <- readTVarIO wmState
  startTime <- getMonotonicTime
  let seatList = Map.toList $ seats state
  let windowList = Map.toList $ windows state
    -- ManageFinish is guaranteed to fire even if something throws
  finally
    (do
        -- set bindings
        -- enable any keybindings that were registered since the last manage sequence
        -- pendingBindings is only non-empty on the first sequence or after new bindings are added
       forConcurrently_ seatList $ \(seatId, seatVal) ->
         forConcurrently_ (pendingBindings seatVal) $ \(ptr, _) ->
           riverXkbBindingV1Enable ptr
        -- focus stuff
        -- only call riverSeatV1FocusWindow if focus actually changed since last time
        -- collect (SeatId, new focus) for the final state update
       newFoci <-
         forConcurrently seatList $ \(seatId, seatVal) -> do
           let current = keyboardFocus seatVal
           let lastSent = lastSentFocus seatVal
           when (current /= lastSent) $ do
             logEvent logger "focus"
               $ "seat " <> show seatId <> " -> " <> show current
             case current of
               Nothing -> riverSeatV1ClearFocus (rawSeat seatVal)
               Just winId ->
                 case Map.lookup winId (windows state) of
                   Nothing -> pure ()
                   Just win ->
                     riverSeatV1FocusWindow (rawSeat seatVal) (rawWindow win)
           pure (seatId, current)
        -- fullscreen stuff
        -- for any window requesting fullscreen, resolve which monitor to use:
        -- if a specific monitor was requested use that, otherwise use the window's current monitor
       forConcurrently_ windowList $ \(_, win) ->
         when (fst (fullscreen win))
           $ let monId =
                   case snd (fullscreen win) of
                     Nothing ->
                       let WorkspaceId (mId, _) = winWorkspace win
                        in mId
                     Just mId -> mId
              in case Map.lookup monId (monitors state) of
                   Nothing -> pure ()
                   Just mon ->
                     riverWindowV1Fullscreen (rawWindow win) (rawOutput mon)
        -- propose dimensions
        -- for each dirty monitor, run the active layout's propose function
        -- collect all proposals so we can update winProposed in state afterward
       allProposals <-
         fmap concat
           $ forConcurrently (Set.toList (dirtyMonitors state)) $ \monId ->
           case Map.lookup monId (monitors state) of
             Nothing -> pure []
             Just mon -> do
               let wsId = activeSpace mon
               case Map.lookup wsId (workspaces state) of
                 Nothing -> pure []
                 Just ws -> do
                   let winIds = wsWindows ws
                   let layout =
                         case layouts ws of
                           (l:_) -> l
                           []    -> SomeLayout Tall
                   let proposals =
                         propose layout mon (marginsFromConfig config) winIds
                   let wcount = length proposals
                   logEvent logger "propose"
                     $ show monId
                         <> " "
                         <> show wcount
                         <> " window"
                         <> (if wcount == 1
                               then ""
                               else "s")
                            -- only send dimensions to River if they actually changed
                            -- (terminals snap to character grid so winGeometry never matches exactly)
                   forConcurrently_ proposals $ \(winId, dims) ->
                     case Map.lookup winId (windows state) of
                       Nothing -> pure ()
                       Just win ->
                         when
                           (winProposed win /= Just (width dims, height dims))
                           $ riverWindowV1ProposeDimensions
                               (rawWindow win)
                               (width dims)
                               (height dims)
                   pure proposals
        -- flush state back to the internal WMState
        -- one atomic update at the end covering all bookkeeping changes
       updateState wmState $ \s ->
         s
           { dirtyMonitors = Set.empty
           , seats =
               foldr
                 (\(seatId, newFocus) acc ->
                    Map.adjust
                      (\seat ->
                         seat
                           { lastSentFocus = newFocus
                           , seatBindings =
                               seatBindings seat ++ pendingBindings seat
                           , pendingBindings = []
                           })
                      seatId
                      acc)
                 (seats s)
                 newFoci
           , windows =
               foldr
                 (\(winId, dims) acc ->
                    Map.adjust
                      (\win ->
                         win {winProposed = Just (width dims, height dims)})
                      winId
                      acc)
                 (windows s)
                 allProposals
           })
    (do
       endTime <- getMonotonicTime
       logEvent logger "manageFinish"
         $ "manage cycle: "
             <> printf "%.3f" ((endTime - startTime) * 1000)
             <> " ms"
       riverWindowManagerV1ManageFinish wmPtr)

onWmRenderStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmRenderStart runtime config wmPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
    -- snapshot state once at the top
  state <- readTVarIO wmState
  startTime <- getMonotonicTime
    -- RenderFinish is guaranteed to fire even if something throws
  finally
    (do
        -- position windows
        -- unlike manage, we render ALL monitors every sequence (not just dirty ones)
        -- render sequences can fire without a preceding manage sequence
        -- e.g. a window independently changes its own dimensions
       allPositions <-
         fmap concat
           $ forConcurrently (Map.elems (monitors state)) $ \mon -> do
           let wsId = activeSpace mon
           case Map.lookup wsId (workspaces state) of
             Nothing -> pure []
             Just ws -> do
               let winIds = wsWindows ws
                    -- build confirmed dimensions from winGeometry for each window
               let dims =
                     mapMaybe
                       (\wId ->
                          fmap
                            (\w ->
                               ( wId
                               , (width (winGeometry w), height (winGeometry w))))
                            (Map.lookup wId (windows state)))
                       winIds
               let layout =
                     case layouts ws of
                       (l:_) -> l
                       []    -> SomeLayout Tall
               let positions =
                     arrange layout mon (marginsFromConfig config) dims
                    -- set the position of each window's node
               forConcurrently positions $ \(winId, rect) ->
                 case Map.lookup winId (windows state) of
                   Nothing -> pure (winId, rect)
                   Just win ->
                     case rawNode win of
                       Nothing -> pure (winId, rect)
                       Just node -> do
                         when (lastPosition win /= Just (x rect, y rect))
                           $ riverNodeV1SetPosition node (x rect) (y rect)
                         pure (winId, rect)
       updateState wmState $ \s ->
         s
           { windows =
               foldr
                 (\(winId, rect) acc ->
                    Map.adjust
                      (\win -> win {lastPosition = Just (x rect, y rect)})
                      winId
                      acc)
                 (windows s)
                 allPositions
           })
    (do
       endTime <- getMonotonicTime
       logEvent logger "renderFinish"
         $ "render cycle: "
             <> printf "%.3f" ((endTime - startTime) * 1000)
             <> " ms"
       riverWindowManagerV1RenderFinish wmPtr)
