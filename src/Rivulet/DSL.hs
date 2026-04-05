module Rivulet.DSL where

import           Rivulet.DSL.Combinators (Combinable (..), LayoutList,
                                          toLayouts)
import           Rivulet.DSL.Keys
import           Rivulet.Monad
import           Rivulet.Types

import           Control.Applicative     ((<|>))
import           Control.Monad           (void)
import           Control.Monad.Writer
import           Data.Functor.Identity
import           Data.Word
import           System.Process          (spawnProcess)

type ConfigM a = WriterT Config Identity a

-- keybinding monad
type KeybindingM a = WriterT [Keybinding] Identity a

bind :: Chord -> RivuletAction -> KeybindingM ()
bind chord action = tell [(chord, action)]

runKeybindings :: KeybindingM () -> [Keybinding]
runKeybindings block = runIdentity $ execWriterT block

keybinds :: KeybindingM () -> ConfigM ()
keybinds k = tell $ mempty {cfgKeybindings = runKeybindings k}

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

instance Binds Chord RivuletAction (KeybindingM ()) where
  (~>) = bind

infix 1 ~>
runRules :: RulesM () -> [Rule]
runRules block = runIdentity $ execWriterT block

rules :: RulesM () -> ConfigM ()
rules r = tell $ mempty {cfgRules = runRules r}

-- autostart monad
type AutostartM a = WriterT [(Maybe String, String)] Identity a

start :: String -> AutostartM ()
start exec = tell [(Nothing, exec)]

startOn :: String -> String -> AutostartM ()
startOn workspace exec = tell [(Just workspace, exec)]

runAutostart :: AutostartM () -> [(Maybe String, String)]
runAutostart block = runIdentity $ execWriterT block

autostart :: AutostartM () -> ConfigM ()
autostart a = tell $ mempty {cfgAutostart = runAutostart a}

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

data Rule =
  Rule String [RuleAction]
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
monitor name wss = tell $ mempty {cfgMonitors = [(name, wss)]}

layout :: LayoutList a => a -> ConfigM ()
layout l = tell $ mempty {cfgLayouts = Just (toLayouts l)}

gaps :: Int -> ConfigM ()
gaps n = tell $ mempty {cfgGaps = Just n}

borders :: Int -> (Word32, Word32) -> ConfigM ()
borders w (unfocused, focused) =
  tell $ mempty {cfgBorders = Just (mkBorder unfocused, mkBorder focused)}
  where
    mkBorder c = Border {edges = 0xf, borderWidth = w, color = c}

debug :: Bool -> ConfigM ()
debug enabled = tell $ mempty {cfgDebug = Just enabled}

-- actions
quit :: RivuletAction
quit = return ()

focusNext :: RivuletAction
focusNext = return ()

focusPrev :: RivuletAction
focusPrev = return ()

swapNext :: RivuletAction
swapNext = return ()

swapPrev :: RivuletAction
swapPrev = return ()

closeFocused :: RivuletAction
closeFocused = return ()

toggleFloat :: RivuletAction
toggleFloat = return ()

toggleFullscreen :: RivuletAction
toggleFullscreen = return ()

cycleLayout :: RivuletAction
cycleLayout = return ()

sendToWorkspace :: String -> RivuletAction
sendToWorkspace _ = return ()

focusWorkspace :: String -> RivuletAction
focusWorkspace _ = return ()

focusMonitor :: String -> RivuletAction
focusMonitor _ = return ()

sendToMonitor :: String -> RivuletAction
sendToMonitor _ = return ()

spawn :: String -> RivuletAction
spawn cmd = liftIO $ void $ spawnProcess cmd []
