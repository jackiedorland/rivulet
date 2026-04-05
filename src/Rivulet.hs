module Rivulet
  ( rivulet
  , gaps
  , debug
  , layout
  , borders
  , monitor
  , keybinds
  , bind
  , rules
  , rule
  , (~>)
  , RuleAction(..)
  , autostart
  , start
  , startOn
  , spawn
  , Full(..)
  , Tall(..)
  , Grid(..)
  , (>>.)
  , (#)
  , (<+>)
  , Combinable(..)
  , just
  , Modifier(..)
  , Chord(..)
  , module Rivulet.DSL.Keysyms
  , focusNext
  , focusPrev
  , swapNext
  , swapPrev
  , closeFocused
  , toggleFloat
  , toggleFullscreen
  , cycleLayout
  , sendToWorkspace
  , focusWorkspace
  , focusMonitor
  , sendToMonitor
  , exitSession
  ) where

import           Rivulet.DSL
import           Rivulet.DSL.Combinators (Combinable (..), (<+>), (>>.))
import           Rivulet.DSL.Keys
import           Rivulet.DSL.Keysyms
import           Rivulet.DSL.Layout      (Full (..), Grid (..), Tall (..))
import           Rivulet.Manager.Runtime (rivulet)
