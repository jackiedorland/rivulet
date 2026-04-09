{- HLINT ignore "Redundant pure" -}
{-# LANGUAGE BlockArguments #-}

module Rivulet.Manager where

import Rivulet.DSL            (Config (..))
import Rivulet.DSL.Layout     (Tall (..))
import Rivulet.FFI.Protocol
import Rivulet.Types

import Control.Concurrent.STM (readTVarIO)
import Control.Exception      (finally)
import Control.Monad          (unless, when)
import Data.List              qualified as List
import Data.Map               qualified as Map
import Data.Maybe
import Data.Set               qualified as Set
import Foreign
import Rivulet.Manager.Log    (Logger, logEvent)
import Rivulet.Monad
import UnliftIO.Async         (forConcurrently, forConcurrently_)

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
                    let winIds = wsWindows ws
                        layout = case layouts ws of (l : _) -> l; [] -> SomeLayout Tall
                        proposals = propose layout mon (marginsFromConfig config) winIds
                        wcount = length proposals
                    logEvent logger "propose" $
                        show monId <> " -> " <> show wcount <> " window" <> if wcount == 1 then "" else "s"
                    -- only send dimensions to River if they actually changed
                    -- (terminals snap to character grid so winGeometry never matches exactly)
                    forConcurrently_ proposals $ \(winId, dims) -> do
                        logEvent logger "propose" $
                            show winId <> " dimensions=" <> show (width dims) <> "×" <> show (height dims)
                        case Map.lookup winId (windows state) of
                            Nothing -> pure ()
                            Just win ->
                                when (winProposed win /= Just (width dims, height dims)) $
                                    riverWindowV1ProposeDimensions (rawWindow win) (width dims) (height dims)
                    pure proposals

positionForMonitor :: Config -> WMState -> Monitor -> IO [(WindowId, Rect)]
positionForMonitor config state mon =
    case Map.lookup (activeSpace mon) (workspaces state) of
        Nothing -> pure []
        Just ws -> do
            let winIds = wsWindows ws
                dims =
                    mapMaybe
                        ( \wId ->
                            case Map.lookup wId (windows state) of
                                Nothing -> Nothing
                                Just win -> Just (wId, (width (winGeometry win), height (winGeometry win)))
                        )
                        winIds
                layout = case layouts ws of (l : _) -> l; [] -> SomeLayout Tall
                positions = arrange layout mon (marginsFromConfig config) dims
            forConcurrently positions $ \(winId, rect) ->
                case Map.lookup winId (windows state) of
                    Nothing -> pure (winId, rect)
                    Just win ->
                        case rawNode win of
                            Nothing -> pure (winId, rect)
                            Just node -> do
                                when (lastPosition win /= Just (x rect, y rect)) $
                                    riverNodeV1SetPosition node (x rect) (y rect)
                                pure (winId, rect)

setBorderForWindow :: WMState -> (Border, Border) -> (WindowId, Window) -> IO ()
setBorderForWindow state (focusedBorder, normalBorder) (winId, win) =
    unless (fst (fullscreen win)) do
        let focused = any (\s -> keyboardFocus s == Just winId) (Map.elems (seats state))
            Border _ w col = if focused then focusedBorder else normalBorder
        riverWindowV1SetBorders (rawWindow win) 0xF w col

onWmManageStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmManageStart runtime config wmPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    -- snapshot state once at the top; safe because the event loop is single-threaded
    state <- readTVarIO wmState
    let seatList = Map.toList $ seats state
        windowList = Map.toList $ windows state
    -- ManageFinish is guaranteed to fire even if something throws
    finally
        ( do
            case Map.lookupMin (layerShellOutputs (layerShell state)) of
                Nothing -> pure ()
                Just (_, layerOutState) ->
                    riverLayerShellOutputV1SetDefault (layerShellOutputPtr layerOutState)

            forConcurrently_ seatList $ \(_, seatVal) ->
                forConcurrently_ (pendingBindings seatVal) $ \(binding, _) ->
                    riverXkbBindingV1Enable binding

            -- only call riverSeatV1FocusWindow if focus actually changed since last time
            newFoci <-
                forConcurrently seatList $ \(seatId, seatVal) -> do
                    let current = keyboardFocus seatVal
                        lastSent = lastSentFocus seatVal
                        exclusiveLayerFocus =
                            maybe
                                False
                                layerShellSeatExclusiveFocus
                                (Map.lookup seatId (layerShellSeats (layerShell state)))
                    if exclusiveLayerFocus
                        then pure (seatId, lastSent)
                        else do
                            when (current /= lastSent) do
                                logEvent logger "focus" $ "seat " <> show seatId <> " -> " <> show current
                                case current of
                                    Nothing ->
                                        riverSeatV1ClearFocus (rawSeat seatVal)
                                    Just winId ->
                                        case Map.lookup winId (windows state) of
                                            Nothing -> pure ()
                                            Just win ->
                                                riverSeatV1FocusWindow (rawSeat seatVal) (rawWindow win)
                            pure (seatId, current)

            -- for any window requesting fullscreen, resolve which monitor to use:
            -- if a specific monitor was requested use that, otherwise use the window's current monitor
            forConcurrently_ windowList $ \(_, win) ->
                when (fst (fullscreen win)) do
                    let monId =
                            case snd (fullscreen win) of
                                Nothing ->
                                    case winWorkspace win of
                                        WorkspaceId (mId, _) -> mId
                                Just mId -> mId
                    case Map.lookup monId (monitors state) of
                        Nothing  -> pure ()
                        Just mon -> riverWindowV1Fullscreen (rawWindow win) (rawOutput mon)

            proposals <-
                fmap concat $
                    forConcurrently (Set.toList (dirtyMonitors state)) $
                        proposeForMonitor logger config state

            updateState wmState $ \s ->
                let applySeatFocus acc (seatId, newFocus) =
                        Map.adjust
                            (\seat ->
                                seat
                                    { lastSentFocus = newFocus
                                    , seatBindings = seatBindings seat ++ pendingBindings seat
                                    , pendingBindings = []
                                    }
                            ) seatId acc
                    applyProposal acc (winId, dims) = Map.adjust
                        (\win -> win{winProposed = Just (width dims, height dims)}) winId acc
                 in s
                        { dirtyMonitors = Set.empty
                        , seats = List.foldl' applySeatFocus (seats s) newFoci
                        , windows = List.foldl' applyProposal (windows s) proposals
                        }
        )
        ( do
            -- logEvent logger "manageFinish" "done"
            riverWindowManagerV1ManageFinish wmPtr
        )

onWmRenderStart :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmRenderStart runtime config wmPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    state <- readTVarIO wmState
    let windowMap = windows state
        liveWindows = Map.keysSet windowMap
        visibleForMonitor monId =
            case Map.lookup monId (monitors state) of
                Nothing -> Set.empty
                Just mon ->
                    case Map.lookup (activeSpace mon) (workspaces state) of
                        Nothing -> Set.empty
                        Just ws ->
                            Set.fromList
                                [ winId
                                | winId <- wsWindows ws
                                , Map.member winId windowMap
                                ]
        monitorWindowsFor monId =
            Set.fromList
                [ winId
                | (WorkspaceId (wsMonId, _), ws) <- Map.toList (workspaces state)
                , wsMonId == monId
                , winId <- wsWindows ws
                , Map.member winId windowMap
                ]
        currentVisibleByMonitor =
            Map.fromList
                [ (monId, visibleForMonitor monId)
                | monId <- Map.keys (monitors state)
                ]
        transitionFor monId =
            let currentVisible =
                    Map.findWithDefault Set.empty monId currentVisibleByMonitor
                previousVisible =
                    Set.intersection
                        liveWindows
                        (Map.findWithDefault Set.empty monId (lastVisibleWindows state))
                monitorWindows = monitorWindowsFor monId
                toHide =
                    case Map.lookup monId (lastVisibleWindows state) of
                        Nothing -> Set.difference monitorWindows currentVisible
                        Just _  -> Set.difference previousVisible currentVisible
                toShow = Set.difference currentVisible previousVisible
             in case (Set.null toHide, Set.null toShow) of
                    (True, True) -> Nothing
                    _            -> Just (monId, toHide, toShow)
        visibilityTransitions =
            mapMaybe transitionFor (Map.keys (monitors state))
    -- RenderFinish is guaranteed to fire even if something throws
    finally
        ( do
            -- render ALL monitors every sequence (not just dirty ones)
            -- render sequences can fire without a preceding manage sequence
            -- e.g. a window independently changes its own dimensions
            allPositions <-
                fmap concat $
                    forConcurrently (Map.elems (monitors state)) $
                        positionForMonitor config state

            case cfgBorders config of
                Nothing -> pure ()
                Just borders ->
                    forConcurrently_ (Map.toList (windows state)) $
                        setBorderForWindow state borders

            forConcurrently_ visibilityTransitions $ \(monId, toHide, toShow) -> do
                logEvent logger "visibility" $
                    show monId
                        <> " hide="
                        <> show (Set.size toHide)
                        <> " show="
                        <> show (Set.size toShow)
                let applyVisibility op winId =
                        case Map.lookup winId windowMap of
                            Nothing  -> pure ()
                            Just win -> op (rawWindow win)
                forConcurrently_ (Set.toList toHide) (applyVisibility riverWindowV1Hide)
                forConcurrently_ (Set.toList toShow) (applyVisibility riverWindowV1Show)

            updateState wmState $ \s ->
                let applyPosition acc (winId, rect) =
                        Map.adjust
                            (\win -> win{lastPosition = Just (x rect, y rect)})
                            winId
                            acc
                 in s
                        { windows = List.foldl' applyPosition (windows s) allPositions
                        , lastVisibleWindows = currentVisibleByMonitor
                        }
        )
        ( do
            -- logEvent logger "renderFinish" "done"
            riverWindowManagerV1RenderFinish wmPtr
        )
