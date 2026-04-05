{-# LANGUAGE PatternSynonyms #-}

module Rivulet.DSL.Keysyms where

import Rivulet.DSL.Keys (Keysym (..), Modifier (..))

-- Function keys
pattern F1  :: Keysym
pattern F1   = Keysym 0xffbe
pattern F2  :: Keysym
pattern F2   = Keysym 0xffbf
pattern F3  :: Keysym
pattern F3   = Keysym 0xffc0
pattern F4  :: Keysym
pattern F4   = Keysym 0xffc1
pattern F5  :: Keysym
pattern F5   = Keysym 0xffc2
pattern F6  :: Keysym
pattern F6   = Keysym 0xffc3
pattern F7  :: Keysym
pattern F7   = Keysym 0xffc4
pattern F8  :: Keysym
pattern F8   = Keysym 0xffc5
pattern F9  :: Keysym
pattern F9   = Keysym 0xffc6
pattern F10 :: Keysym
pattern F10  = Keysym 0xffc7
pattern F11 :: Keysym
pattern F11  = Keysym 0xffc8
pattern F12 :: Keysym
pattern F12  = Keysym 0xffc9

-- Navigation
pattern Return    :: Keysym
pattern Return     = Keysym 0xff0d
pattern Space     :: Keysym
pattern Space      = Keysym 0x0020
pattern Tab       :: Keysym
pattern Tab        = Keysym 0xff09
pattern Escape    :: Keysym
pattern Escape     = Keysym 0xff1b
pattern BackSpace :: Keysym
pattern BackSpace  = Keysym 0xff08
pattern Delete    :: Keysym
pattern Delete     = Keysym 0xffff
pattern Insert    :: Keysym
pattern Insert     = Keysym 0xff63
pattern Home      :: Keysym
pattern Home       = Keysym 0xff50
pattern End       :: Keysym
pattern End        = Keysym 0xff57
pattern PageUp    :: Keysym
pattern PageUp     = Keysym 0xff55
pattern PageDown  :: Keysym
pattern PageDown   = Keysym 0xff56
pattern Super     :: Modifier
pattern Super      = Mod4
pattern Alt       :: Modifier
pattern Alt        = Mod1
pattern Ctrl      :: Modifier
pattern Ctrl       = Control

-- Arrow keys
pattern Left  :: Keysym
pattern Left   = Keysym 0xff51
pattern Up    :: Keysym
pattern Up     = Keysym 0xff52
pattern Right :: Keysym
pattern Right  = Keysym 0xff53
pattern Down  :: Keysym
pattern Down   = Keysym 0xff54

-- Media keys
pattern XF86AudioRaiseVolume :: Keysym
pattern XF86AudioRaiseVolume  = Keysym 0x1008ff13
pattern XF86AudioLowerVolume :: Keysym
pattern XF86AudioLowerVolume  = Keysym 0x1008ff11
pattern XF86AudioMute        :: Keysym
pattern XF86AudioMute         = Keysym 0x1008ff12
pattern XF86AudioPlay        :: Keysym
pattern XF86AudioPlay         = Keysym 0x1008ff14
pattern XF86AudioStop        :: Keysym
pattern XF86AudioStop         = Keysym 0x1008ff15
pattern XF86AudioPrev        :: Keysym
pattern XF86AudioPrev         = Keysym 0x1008ff16
pattern XF86AudioNext        :: Keysym
pattern XF86AudioNext         = Keysym 0x1008ff17
pattern XF86MonBrightnessUp  :: Keysym
pattern XF86MonBrightnessUp   = Keysym 0x1008ff02
pattern XF86MonBrightnessDown :: Keysym
pattern XF86MonBrightnessDown  = Keysym 0x1008ff03

-- Numpad
pattern KP0      :: Keysym
pattern KP0       = Keysym 0xffb0
pattern KP1      :: Keysym
pattern KP1       = Keysym 0xffb1
pattern KP2      :: Keysym
pattern KP2       = Keysym 0xffb2
pattern KP3      :: Keysym
pattern KP3       = Keysym 0xffb3
pattern KP4      :: Keysym
pattern KP4       = Keysym 0xffb4
pattern KP5      :: Keysym
pattern KP5       = Keysym 0xffb5
pattern KP6      :: Keysym
pattern KP6       = Keysym 0xffb6
pattern KP7      :: Keysym
pattern KP7       = Keysym 0xffb7
pattern KP8      :: Keysym
pattern KP8       = Keysym 0xffb8
pattern KP9      :: Keysym
pattern KP9       = Keysym 0xffb9
pattern KPEnter  :: Keysym
pattern KPEnter   = Keysym 0xff8d
pattern KPAdd    :: Keysym
pattern KPAdd     = Keysym 0xffab
pattern KPSubtract :: Keysym
pattern KPSubtract = Keysym 0xffad
pattern KPMultiply :: Keysym
pattern KPMultiply = Keysym 0xffaa
pattern KPDivide :: Keysym
pattern KPDivide   = Keysym 0xffaf
