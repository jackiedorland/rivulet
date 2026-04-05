module Rivulet.DSL.Keys where

import           Rivulet.DSL.Combinators (Combinable (..))
import           Rivulet.Monad           (RivuletAction)

import           Data.Bits
import           Data.List               (foldl')
import           Data.Word

modifierMask :: Modifier -> Word32
modifierMask Shift   = 0x01
modifierMask Control = 0x04
modifierMask Mod1    = 0x08
modifierMask Mod2    = 0x10
modifierMask Mod3    = 0x20
modifierMask Mod4    = 0x40
modifierMask Mod5    = 0x80

modifiersMask :: [Modifier] -> Word32
modifiersMask = foldl' (\acc m -> acc .|. modifierMask m) 0

newtype Keysym =
  Keysym Word32
  deriving (Show)

class Key a where
  toKeysym :: a -> Keysym

instance Key Keysym where
  toKeysym = id

instance Key Char where
  toKeysym c = Keysym $ fromIntegral (fromEnum c)

class Modifiers m where
  toModifiers :: m -> [Modifier]

instance Modifiers Modifier where
  toModifiers m = [m]

instance Modifiers [Modifier] where
  toModifiers = id

infixl 5 #
(#) :: (Modifiers m, Key a) => m -> a -> Chord
ms # k = Chord (toModifiers ms) (toKeysym k)

just :: Key a => a -> Chord
just = (([] :: [Modifier]) #)

type Keybinding = (Chord, RivuletAction)

data Chord =
  Chord [Modifier] Keysym
  deriving (Show)

data Modifier
  = Shift
  | Control
  | Mod1
  | Mod2
  | Mod3
  | Mod4
  | Mod5
  deriving (Show)

instance Combinable Modifier Modifier where
  items m = [m]

instance Combinable [Modifier] Modifier where
  items = id
