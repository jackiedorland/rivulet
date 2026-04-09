module Rivulet.DSL where

import Rivulet.DSL.Combinators (Combinable (..), LayoutList, toLayouts)
import Rivulet.DSL.Keys
import Rivulet.FFI.Protocol    (riverWindowManagerV1ExitSession, riverWindowManagerV1ManageDirty,
                                riverWindowV1Close)
import Rivulet.Monad
import Rivulet.Types

import Control.Applicative     ((<|>))
import Control.Monad           (void)
import Control.Monad.Writer
import Data.Functor.Identity
import Data.List               (find)
import Data.Map.Strict         qualified as Map
import Data.Set                qualified as Set
import Data.Word
import System.Process          (spawnProcess)

type ConfigM a = WriterT Config Identity a

-- keybinding monad
type KeybindingM a = WriterT [Keybinding] Identity a

bind :: Chord -> Action -> KeybindingM ()
bind chord action = tell [(chord, action)]

bindEach :: (Foldable t, Modifiers m, Key a) => m -> t a -> (a -> Action) -> KeybindingM ()
bindEach mods keys actionFor =
    mapM_ (\key -> bind (mods # key) (actionFor key)) keys

focusWorkspaceNumbers :: (Modifiers m) => m -> [String] -> KeybindingM ()
focusWorkspaceNumbers mods names =
    mapM_
        (\(key, name) -> bind (mods # key) (focusWorkspace name))
        (zip ['1' .. '9'] names)

sendToWorkspaceNumbers :: (Modifiers m) => m -> [String] -> KeybindingM ()
sendToWorkspaceNumbers mods names =
    mapM_
        (\(key, name) -> bind (mods # key) (sendToWorkspace name))
        (zip ['1' .. '9'] names)

runKeybindings :: KeybindingM () -> [Keybinding]
runKeybindings block = runIdentity $ execWriterT block

keybinds :: KeybindingM () -> ConfigM ()
keybinds k = tell $ mempty{cfgKeybindings = runKeybindings k}

-- rules monad
type RulesM a = WriterT [Rule] Identity a

rule :: String -> [RuleAction] -> RulesM ()
rule name actions = tell [Rule name actions]

class Binds a b r | a b -> r where
    (~>) :: a -> b -> r

instance Binds String RuleAction (RulesM ()) where
    (~>) name action = rule name [action]

instance Binds String [RuleAction] (RulesM ()) where
    (~>) = rule

instance Combinable RuleAction RuleAction where
    items a = [a]

instance Combinable [RuleAction] RuleAction where
    items = id

instance Binds Chord Action (KeybindingM ()) where
    (~>) = bind

instance (Key a) => Binds (ChordPattern a) (a -> Action) (KeybindingM ()) where
    (~>) (ChordPattern mods keys) actionFor =
        mapM_ (\key -> bind (mods # key) (actionFor key)) keys

instance Binds (ChordPattern Char) (String -> Action) (KeybindingM ()) where
    (~>) (ChordPattern mods keys) actionFor =
        mapM_ (\key -> bind (mods # key) (actionFor [key])) keys

infix 1 ~>
runRules :: RulesM () -> [Rule]
runRules block = runIdentity $ execWriterT block

rules :: RulesM () -> ConfigM ()
rules r = tell $ mempty{cfgRules = runRules r}

-- autostart monad
type AutostartM a = WriterT [(Maybe String, String)] Identity a

start :: String -> AutostartM ()
start exec = tell [(Nothing, exec)]

startOn :: String -> String -> AutostartM ()
startOn workspace exec = tell [(Just workspace, exec)]

runAutostart :: AutostartM () -> [(Maybe String, String)]
runAutostart block = runIdentity $ execWriterT block

autostart :: AutostartM () -> ConfigM ()
autostart a = tell $ mempty{cfgAutostart = runAutostart a}

data Config = Config
    { cfgMonitors    :: [(String, [String])]
    , cfgLayouts     :: Maybe [SomeLayout]
    , cfgGaps        :: Maybe Int -- Nothing = 0
    , cfgBorders     :: Maybe (Border, Border)
    , cfgDebug       :: Maybe Bool
    , cfgRules       :: [Rule]
    , cfgKeybindings :: [Keybinding]
    , cfgAutostart   :: [(Maybe String, String)]
    }

data Rule
    = Rule String [RuleAction]
    deriving (Show)

data RuleAction
    = Floating
    | OnWorkspace String
    | Fullscreen
    | NoBorders
    | Center
    | Size Int Int
    | AlwaysOnTop
    | Sticky
    deriving (Show)

-- Config instance
instance Semigroup Config where
    a <> b =
        Config
            { cfgMonitors = cfgMonitors a <> cfgMonitors b
            , cfgLayouts = cfgLayouts b <|> cfgLayouts a -- last wins
            , cfgGaps = cfgGaps b <|> cfgGaps a -- last wins
            , cfgBorders = cfgBorders b <|> cfgBorders a -- last wins
            , cfgDebug = cfgDebug b <|> cfgDebug a -- last wins
            , cfgRules = cfgRules a <> cfgRules b
            , cfgKeybindings = cfgKeybindings a <> cfgKeybindings b
            , cfgAutostart = cfgAutostart a <> cfgAutostart b
            }

instance Monoid Config where
    mempty =
        Config
            { cfgMonitors = []
            , cfgLayouts = Nothing
            , cfgGaps = Nothing
            , cfgBorders = Nothing
            , cfgDebug = Nothing
            , cfgRules = []
            , cfgKeybindings = []
            , cfgAutostart = []
            }

-- config DSL
monitor :: String -> [String] -> ConfigM ()
monitor name wss = tell $ mempty{cfgMonitors = [(name, wss)]}

layout :: (LayoutList a) => a -> ConfigM ()
layout l = tell $ mempty{cfgLayouts = Just (toLayouts l)}

gaps :: Int -> ConfigM ()
gaps n = tell $ mempty{cfgGaps = Just n}

borders :: Int -> (Word32, Word32) -> ConfigM ()
borders w (unfocused, focused) =
    tell $ mempty{cfgBorders = Just (mkBorder unfocused, mkBorder focused)}
  where
    mkBorder c = Border{edges = 0xF, borderWidth = w, color = c}

debug :: Bool -> ConfigM ()
debug enabled = tell $ mempty{cfgDebug = Just enabled}

-- actions
exitSession :: Action
exitSession = do
    state <- getState
    liftIO $ riverWindowManagerV1ExitSession (rawWM state)

closeFocused :: Action
closeFocused = withFocused $ \_ win ->
    liftIO $ riverWindowV1Close (rawWindow win)

focusNext :: Action
focusNext = return ()

focusPrev :: Action
focusPrev = return ()

swapNext :: Action
swapNext = return ()

swapPrev :: Action
swapPrev = return ()

toggleFloat :: Action
toggleFloat = return ()

toggleFullscreen :: Action
toggleFullscreen = return ()

cycleLayout :: Action
cycleLayout = return ()

findWorkspaceIdByName :: WMState -> String -> Maybe WorkspaceId
findWorkspaceIdByName state name =
    fst <$> find ((== name) . wsName . snd) (Map.toList (workspaces state))

appendWindowUnique :: WindowId -> [WindowId] -> [WindowId]
appendWindowUnique winId wsWins =
    if winId `elem` wsWins
        then wsWins
        else wsWins ++ [winId]

moveWindowBetweenWorkspaces :: WindowId -> WorkspaceId -> WorkspaceId -> WMState -> WMState
moveWindowBetweenWorkspaces winId sourceWs targetWs s =
    s
        { windows = Map.adjust (\w -> w{winWorkspace = targetWs}) winId (windows s)
        , workspaces =
            Map.adjust
                (\ws -> ws{wsWindows = appendWindowUnique winId (wsWindows ws)})
                targetWs
                $ Map.adjust
                    (\ws -> ws{wsWindows = filter (/= winId) (wsWindows ws)})
                    sourceWs
                    (workspaces s)
        }

clearFocusForWindow :: WindowId -> WMState -> WMState
clearFocusForWindow winId s =
    s{seats = Map.map clearSeat (seats s)}
  where
    clearSeat seat
        | keyboardFocus seat == Just winId = seat{keyboardFocus = Nothing}
        | otherwise = seat

clearFocusOutsideWorkspaceOnMonitor :: MonitorId -> WorkspaceId -> WMState -> WMState
clearFocusOutsideWorkspaceOnMonitor monId targetWs s =
    s{seats = Map.map clearSeat (seats s)}
  where
    clearSeat seat =
        case keyboardFocus seat >>= (\wId -> Map.lookup wId (windows s)) of
            Just win ->
                let WorkspaceId (focusMon, _) = winWorkspace win
                 in if focusMon == monId && winWorkspace win /= targetWs
                        then seat{keyboardFocus = Nothing}
                        else seat
            Nothing -> seat

isWorkspaceVisibleOnMonitor :: WMState -> MonitorId -> WorkspaceId -> Bool
isWorkspaceVisibleOnMonitor state monId targetWs =
    case Map.lookup monId (monitors state) of
        Nothing  -> False
        Just mon -> activeSpace mon == targetWs

sendToWorkspace :: String -> Action
sendToWorkspace targetName = withFocused $ \winId win -> do
    state <- getState
    case findWorkspaceIdByName state targetName of
        Nothing -> pure ()
        Just targetWs
            | targetWs == winWorkspace win -> pure ()
            | otherwise -> do
                let sourceWs@(WorkspaceId (sourceMon, _)) = winWorkspace win
                    WorkspaceId (targetMon, _) = targetWs
                    targetVisible = isWorkspaceVisibleOnMonitor state targetMon targetWs
                update $ \s ->
                    let moved = moveWindowBetweenWorkspaces winId sourceWs targetWs s
                        marked =
                            moved
                                { dirtyMonitors =
                                    Set.insert sourceMon (Set.insert targetMon (dirtyMonitors moved))
                                }
                     in if targetVisible
                            then marked
                            else clearFocusForWindow winId marked
                state' <- getState
                liftIO $ riverWindowManagerV1ManageDirty (rawWM state')

focusWorkspace :: String -> Action
focusWorkspace targetName = do
    state <- getState
    case findWorkspaceIdByName state targetName of
        Nothing -> pure ()
        Just targetWs@(WorkspaceId (targetMon, _)) -> do
            update $ \s ->
                let switched =
                        s
                            { monitors =
                                Map.adjust
                                    (\m -> m{activeSpace = targetWs})
                                    targetMon
                                    (monitors s)
                            , dirtyMonitors = Set.insert targetMon (dirtyMonitors s)
                            }
                 in clearFocusOutsideWorkspaceOnMonitor targetMon targetWs switched
            state' <- getState
            liftIO $ riverWindowManagerV1ManageDirty (rawWM state')

focusMonitor :: String -> Action
focusMonitor _ = return ()

sendToMonitor :: String -> Action
sendToMonitor _ = return ()

spawn :: String -> Action
spawn cmd = liftIO $ void $ spawnProcess cmd []
