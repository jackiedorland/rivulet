module Fjord.Runtime where

import Fjord.Model

import Control.Concurrent.STM
import Data.Map
import Data.IORef
import Fjord.Callbacks
import Fjord.Log

data Runtime = Runtime {
    state :: IORef State
  , events :: TQueue Event
  , destructors :: IORef (Map ObjectId Destructor)
  , log :: TQueue Msg
}