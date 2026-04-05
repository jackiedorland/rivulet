{-# LANGUAGE CApiFFI         #-}
{-# LANGUAGE RecordWildCards #-}

-- | High-level Wayland protocol bindings for River window manager.
--
-- This module provides type-safe Haskell bindings to River's custom Wayland protocols:
-- - @river_window_management_v1@ — Frame-perfect window management
-- - @river_xkb_bindings_v1@ — Keyboard binding management with xkbcommon
-- - @river_input_management_v1@ — Input device management
--
-- The module also exports Wayland core types (@wl_surface@, @wl_output@)
-- and fixed-point arithmetic utilities.
--
-- == Basic Usage
--
-- Typical window manager initialization:
--
-- > import Rivulet.FFI.Client
-- > import Rivulet.FFI.Protocol
-- >
-- > -- Connect and get registry
-- > Just display <- wlDisplayConnect Nothing
-- > registry <- wlDisplayGetRegistry display
-- >
-- > -- Set up registry listener to bind globals
-- > -- When river_window_manager_v1 becomes available:
-- > wm <- wlRegistryBind registry wmName riverWindowManagerV1Interface 4
-- >
-- > -- Create and attach listener
-- > listener <- createWindowManagerListener  -- your listener implementation
-- > cleanup <- riverWindowManagerV1AddListener wm listener
--
-- == Protocol Sequences
--
-- The window manager protocol uses a manage/render sequence pattern:
-- 1. 'onWmManageStart' event arrives from compositor
-- > 2. Modify window management state via requests (focus, dimensions, etc.)
-- 3. Call 'riverWindowManagerV1ManageFinish' to atomically apply changes
-- 4. 'onWmRenderStart' event arrives
-- 5. Modify rendering state (positions, borders, decorations)
-- 6. Call 'riverWindowManagerV1RenderFinish' to display changes
--
-- == Memory Management
--
-- - Listener cleanups returned by 'riverWindowManagerV1AddListener' must be called
--   to free function pointers when shutting down.
-- - Opaque types should be destroyed with their respective @_destroy@ functions.
-- - No manual memory management is needed for display connections
--   (handled by 'Rivulet.FFI.Client').

module Rivulet.FFI.Protocol
    ( -- * external wayland types
      WlOutput
    , WlSurface
      -- * wayland fixed-point
    , WlFixed (..)
    , fromWlFixed
    , toWlFixed
      -- * opaque river types
    , RiverDecorationV1
    , RiverInputDeviceV1
    , RiverInputManagerV1
    , RiverNodeV1
    , RiverOutputV1
    , RiverPointerBindingV1
    , RiverSeatV1
    , RiverShellSurfaceV1
    , RiverWindowManagerV1
    , RiverWindowV1
    , RiverXkbBindingV1
    , RiverXkbBindingsSeatV1
    , RiverXkbBindingsV1
      -- * interface pointers for wlRegistryBind
    , riverInputManagerV1Interface
    , riverWindowManagerV1Interface
    , riverXkbBindingsV1Interface
      -- * window manager requests
    , riverWindowManagerV1Destroy
    , riverWindowManagerV1ExitSession
    , riverWindowManagerV1GetShellSurface
    , riverWindowManagerV1ManageDirty
    , riverWindowManagerV1ManageFinish
    , riverWindowManagerV1RenderFinish
    , riverWindowManagerV1Stop
      -- * window manager events
    , WindowManagerListener (..)
    , riverWindowManagerV1AddListener
      -- * window requests
    , riverWindowV1Close
    , riverWindowV1Destroy
    , riverWindowV1ExitFullscreen
    , riverWindowV1Fullscreen
    , riverWindowV1GetDecorationAbove
    , riverWindowV1GetDecorationBelow
    , riverWindowV1GetNode
    , riverWindowV1Hide
    , riverWindowV1InformFullscreen
    , riverWindowV1InformMaximized
    , riverWindowV1InformNotFullscreen
    , riverWindowV1InformResizeEnd
    , riverWindowV1InformResizeStart
    , riverWindowV1InformUnmaximized
    , riverWindowV1ProposeDimensions
    , riverWindowV1SetBorders
    , riverWindowV1SetCapabilities
    , riverWindowV1SetClipBox
    , riverWindowV1SetContentClipBox
    , riverWindowV1SetDimensionBounds
    , riverWindowV1SetTiled
    , riverWindowV1Show
    , riverWindowV1UseCsd
    , riverWindowV1UseSsd
      -- * window events
    , WindowListener (..)
    , riverWindowV1AddListener
      -- * decoration requests
    , riverDecorationV1Destroy
    , riverDecorationV1SetOffset
    , riverDecorationV1SyncNextCommit
      -- * shell surface requests
    , riverShellSurfaceV1Destroy
    , riverShellSurfaceV1GetNode
    , riverShellSurfaceV1SyncNextCommit
      -- * node requests
    , riverNodeV1Destroy
    , riverNodeV1PlaceAbove
    , riverNodeV1PlaceBelow
    , riverNodeV1PlaceBottom
    , riverNodeV1PlaceTop
    , riverNodeV1SetPosition
      -- * output requests + events
    , OutputListener (..)
    , riverOutputV1AddListener
    , riverOutputV1Destroy
    , riverOutputV1SetPresentationMode
      -- * seat requests + events
    , SeatListener (..)
    , riverSeatV1AddListener
    , riverSeatV1ClearFocus
    , riverSeatV1Destroy
    , riverSeatV1FocusShellSurface
    , riverSeatV1FocusWindow
    , riverSeatV1GetPointerBinding
    , riverSeatV1OpEnd
    , riverSeatV1OpStartPointer
    , riverSeatV1PointerWarp
    , riverSeatV1SetXcursorTheme
      -- * pointer binding
    , PointerBindingListener (..)
    , riverPointerBindingV1AddListener
    , riverPointerBindingV1Destroy
    , riverPointerBindingV1Disable
    , riverPointerBindingV1Enable
      -- * xkb bindings
    , XkbBindingListener (..)
    , XkbBindingsSeatListener (..)
    , riverXkbBindingV1AddListener
    , riverXkbBindingV1Destroy
    , riverXkbBindingV1Disable
    , riverXkbBindingV1Enable
    , riverXkbBindingV1SetLayoutOverride
    , riverXkbBindingsSeatV1AddListener
    , riverXkbBindingsSeatV1CancelEnsureNextKeyEaten
    , riverXkbBindingsSeatV1Destroy
    , riverXkbBindingsSeatV1EnsureNextKeyEaten
    , riverXkbBindingsV1Destroy
    , riverXkbBindingsV1GetSeat
    , riverXkbBindingsV1GetXkbBinding
      -- * input manager
    , InputManagerListener (..)
    , riverInputManagerV1AddListener
    , riverInputManagerV1CreateSeat
    , riverInputManagerV1Destroy
    , riverInputManagerV1DestroySeat
    , riverInputManagerV1Stop
      -- * input device
    , InputDeviceListener (..)
    , riverInputDeviceV1AddListener
    , riverInputDeviceV1AssignToSeat
    , riverInputDeviceV1Destroy
    , riverInputDeviceV1MapToOutput
    , riverInputDeviceV1MapToRectangle
    , riverInputDeviceV1SetRepeatInfo
    , riverInputDeviceV1SetScrollFactor
    ) where

import Foreign
import Foreign.C.String   (CString, peekCString, withCString)
import Foreign.C.Types    (CInt (..), CUInt (..))

import Rivulet.FFI.Client (WlInterface, WlProxy)

----- external wayland types

data WlSurface
data WlOutput

----- wayland fixed-point (int32 with 8 fractional bits)

newtype WlFixed = WlFixed CInt deriving (Eq, Show)

toWlFixed :: Double -> WlFixed
toWlFixed = WlFixed . round . (* 256)

fromWlFixed :: WlFixed -> Double
fromWlFixed (WlFixed n) = fromIntegral n / 256

----- opaque river types

data RiverWindowManagerV1
data RiverWindowV1
data RiverDecorationV1
data RiverShellSurfaceV1
data RiverNodeV1
data RiverOutputV1
data RiverSeatV1
data RiverPointerBindingV1
data RiverXkbBindingsV1
data RiverXkbBindingV1
data RiverXkbBindingsSeatV1
data RiverInputManagerV1
data RiverInputDeviceV1

----- helpers

foreign import capi "rivulet_helpers.h rivulet_proxy_add_listener"
  wl_proxy_add_listener :: Ptr WlProxy -> Ptr (FunPtr (IO ())) -> Ptr () -> IO CInt

nullableStr :: CString -> IO (Maybe String)
nullableStr p
  | p == nullPtr = pure Nothing
  | otherwise    = Just <$> peekCString p

nullablePtr :: Ptr a -> Maybe (Ptr a)
nullablePtr p
  | p == nullPtr = Nothing
  | otherwise    = Just p

fi :: (Integral a, Num b) => a -> b
fi = fromIntegral

----- interface pointers

foreign import capi "river-window-management-v1.h &river_window_manager_v1_interface"
  riverWindowManagerV1Interface :: Ptr WlInterface

foreign import capi "river-xkb-bindings-v1.h &river_xkb_bindings_v1_interface"
  riverXkbBindingsV1Interface :: Ptr WlInterface

foreign import capi "river-input-management-v1.h &river_input_manager_v1_interface"
  riverInputManagerV1Interface :: Ptr WlInterface

-- | Window manager request functions for the river_window_manager_v1 protocol interface.
-- These are typically called in response to 'onWmManageStart' events.

-- | Stop sending events.
--
-- Indicates the client no longer wishes to receive events on this manager.
-- The server may continue sending events asynchronously until acknowledged.
-- Must wait for 'onWmFinished' before destroying the object.
riverWindowManagerV1Stop :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1Stop = river_window_manager_v1_stop

foreign import capi "river-window-management-v1.h river_window_manager_v1_stop"
  river_window_manager_v1_stop :: Ptr RiverWindowManagerV1 -> IO ()

-- | Destroy the window manager object.
--
-- Should only be called after 'onWmFinished' has been received.
-- This completes the shutdown sequence initiated by 'riverWindowManagerV1Stop'.
riverWindowManagerV1Destroy :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1Destroy = river_window_manager_v1_destroy

foreign import capi "river-window-management-v1.h river_window_manager_v1_destroy"
  river_window_manager_v1_destroy :: Ptr RiverWindowManagerV1 -> IO ()

-- | Finish a manage sequence.
--
-- Sent after modifying window management state (dimensions, focus, etc.)
-- in response to a 'onWmManageStart' event. Signals the compositor to
-- atomically apply all pending state changes to windows.
-- A protocol error occurs if called outside a manage sequence.
riverWindowManagerV1ManageFinish :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1ManageFinish = river_window_manager_v1_manage_finish

foreign import capi "river-window-management-v1.h river_window_manager_v1_manage_finish"
  river_window_manager_v1_manage_finish :: Ptr RiverWindowManagerV1 -> IO ()

-- | Request that a manage sequence be started.
--
-- Used when internal state has changed (e.g., via D-Bus event)
-- that the compositor is unaware of. Ensures a 'onWmManageStart'
-- event is sent by the server. If already in a manage sequence,
-- starts a new one after the current one completes.
riverWindowManagerV1ManageDirty :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1ManageDirty = river_window_manager_v1_manage_dirty

foreign import capi "river-window-management-v1.h river_window_manager_v1_manage_dirty"
  river_window_manager_v1_manage_dirty :: Ptr RiverWindowManagerV1 -> IO ()

-- | Finish a render sequence.
--
-- Sent after modifying rendering state (window positions, borders, etc.)
-- in response to a 'onWmRenderStart' event. The compositor applies and
-- displays all pending rendering changes to the user.
-- A protocol error occurs if called outside a render sequence.
riverWindowManagerV1RenderFinish :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1RenderFinish = river_window_manager_v1_render_finish

foreign import capi "river-window-management-v1.h river_window_manager_v1_render_finish"
  river_window_manager_v1_render_finish :: Ptr RiverWindowManagerV1 -> IO ()

-- | Create a shell surface for window manager UI.
--
-- Assigns the @river_shell_surface_v1@ role to the given surface.
-- Returns a shell surface object for managing UI elements (e.g., panels).
-- The surface must not already have a role or any buffered content.
riverWindowManagerV1GetShellSurface
  :: Ptr RiverWindowManagerV1 -> Ptr WlSurface -> IO (Ptr RiverShellSurfaceV1)
riverWindowManagerV1GetShellSurface = river_window_manager_v1_get_shell_surface

foreign import capi "river-window-management-v1.h river_window_manager_v1_get_shell_surface"
  river_window_manager_v1_get_shell_surface
    :: Ptr RiverWindowManagerV1 -> Ptr WlSurface -> IO (Ptr RiverShellSurfaceV1)

-- | Exit the Wayland session.
--
-- Requests that the compositor exit the current Wayland session.
-- Typically used when shutting down the window manager.
riverWindowManagerV1ExitSession :: Ptr RiverWindowManagerV1 -> IO ()
riverWindowManagerV1ExitSession = river_window_manager_v1_exit_session

foreign import capi "river-window-management-v1.h river_window_manager_v1_exit_session"
  river_window_manager_v1_exit_session :: Ptr RiverWindowManagerV1 -> IO ()

-- | Window manager event listeners.
-- These callbacks are invoked by the compositor during 'wlDisplayDispatch' or 'wlDisplayRoundtrip'.

-- C-level callback signatures for FFI marshaling
type RawWmUnavailable   = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmFinished      = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmManageStart   = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmRenderStart   = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmSessionLocked = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmSessionUnlocked = Ptr () -> Ptr RiverWindowManagerV1 -> IO ()
type RawWmWindow        = Ptr () -> Ptr RiverWindowManagerV1 -> Ptr RiverWindowV1 -> IO ()
type RawWmOutput        = Ptr () -> Ptr RiverWindowManagerV1 -> Ptr RiverOutputV1 -> IO ()
type RawWmSeat          = Ptr () -> Ptr RiverWindowManagerV1 -> Ptr RiverSeatV1   -> IO ()

foreign import ccall "wrapper" mkRawWmUnavailable    :: RawWmUnavailable    -> IO (FunPtr RawWmUnavailable)
foreign import ccall "wrapper" mkRawWmFinished       :: RawWmFinished       -> IO (FunPtr RawWmFinished)
foreign import ccall "wrapper" mkRawWmManageStart    :: RawWmManageStart    -> IO (FunPtr RawWmManageStart)
foreign import ccall "wrapper" mkRawWmRenderStart    :: RawWmRenderStart    -> IO (FunPtr RawWmRenderStart)
foreign import ccall "wrapper" mkRawWmSessionLocked  :: RawWmSessionLocked  -> IO (FunPtr RawWmSessionLocked)
foreign import ccall "wrapper" mkRawWmSessionUnlocked :: RawWmSessionUnlocked -> IO (FunPtr RawWmSessionUnlocked)
foreign import ccall "wrapper" mkRawWmWindow         :: RawWmWindow         -> IO (FunPtr RawWmWindow)
foreign import ccall "wrapper" mkRawWmOutput         :: RawWmOutput         -> IO (FunPtr RawWmOutput)
foreign import ccall "wrapper" mkRawWmSeat           :: RawWmSeat           -> IO (FunPtr RawWmSeat)

-- | Listener record for window manager events.
--
-- Each field is a callback that receives the manager pointer and event-specific arguments.
-- Populate all fields with appropriate handlers and pass to 'riverWindowManagerV1AddListener'.
data WindowManagerListener = WindowManagerListener
  { onWmUnavailable     :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ Window management is unavailable (another client already managing).
    -- This is the first and only event if sent.
  , onWmFinished        :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ Server has finished with the window manager.
    -- Safe to call 'riverWindowManagerV1Destroy' after this.
  , onWmManageStart     :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ Start a manage sequence. Modify window management state, then call
    -- 'riverWindowManagerV1ManageFinish'. See protocol description for full sequence.
  , onWmRenderStart     :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ Start a render sequence. Modify rendering state (positions, borders),
    -- then call 'riverWindowManagerV1RenderFinish'.
  , onWmSessionLocked   :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ The Wayland session has been locked.
  , onWmSessionUnlocked :: Ptr RiverWindowManagerV1 -> IO ()
    -- ^ The Wayland session has been unlocked.
  , onWmWindow          :: Ptr RiverWindowManagerV1 -> Ptr RiverWindowV1 -> IO ()
    -- ^ A new window is available for management.
  , onWmOutput          :: Ptr RiverWindowManagerV1 -> Ptr RiverOutputV1 -> IO ()
    -- ^ A new output (display) is available.
  , onWmSeat            :: Ptr RiverWindowManagerV1 -> Ptr RiverSeatV1 -> IO ()
    -- ^ A new seat (input device collection) is available.
  }

-- | Register event listeners for the window manager.
--
-- Returns a cleanup action that should be called when the manager is no longer needed.
-- This cleanup frees the callback function pointers. Call this action before exiting.
riverWindowManagerV1AddListener
  :: Ptr RiverWindowManagerV1 -> WindowManagerListener -> IO (IO ())
riverWindowManagerV1AddListener wm WindowManagerListener{..} = do
  fp0 <- mkRawWmUnavailable     $ \_ w   -> onWmUnavailable w
  fp1 <- mkRawWmFinished        $ \_ w   -> onWmFinished w
  fp2 <- mkRawWmManageStart     $ \_ w   -> onWmManageStart w
  fp3 <- mkRawWmRenderStart     $ \_ w   -> onWmRenderStart w
  fp4 <- mkRawWmSessionLocked   $ \_ w   -> onWmSessionLocked w
  fp5 <- mkRawWmSessionUnlocked $ \_ w   -> onWmSessionUnlocked w
  fp6 <- mkRawWmWindow          $ \_ w win -> onWmWindow w win
  fp7 <- mkRawWmOutput          $ \_ w o   -> onWmOutput w o
  fp8 <- mkRawWmSeat            $ \_ w s   -> onWmSeat w s
  lp  <- newArray [ castFunPtr fp0, castFunPtr fp1, castFunPtr fp2
                  , castFunPtr fp3, castFunPtr fp4, castFunPtr fp5
                  , castFunPtr fp6, castFunPtr fp7, castFunPtr fp8 :: FunPtr (IO ()) ]
  _ <- wl_proxy_add_listener (castPtr wm) lp nullPtr
  pure $ do
    mapM_ freeHaskellFunPtr
      [castFunPtr fp0, castFunPtr fp1, castFunPtr fp2, castFunPtr fp3
      ,castFunPtr fp4, castFunPtr fp5, castFunPtr fp6, castFunPtr fp7
      ,castFunPtr fp8 :: FunPtr (IO ())]
    free lp

-- | Window request functions for managing individual windows.
-- These are typically called during a manage or render sequence.

-- | Destroy the window object.
riverWindowV1Destroy :: Ptr RiverWindowV1 -> IO ()
riverWindowV1Destroy = river_window_v1_destroy

foreign import capi "river-window-management-v1.h river_window_v1_destroy"
  river_window_v1_destroy :: Ptr RiverWindowV1 -> IO ()

-- | Request that the window be closed.
--
-- Sends a close event to the client application.
riverWindowV1Close :: Ptr RiverWindowV1 -> IO ()
riverWindowV1Close = river_window_v1_close

foreign import capi "river-window-management-v1.h river_window_v1_close"
  river_window_v1_close :: Ptr RiverWindowV1 -> IO ()

-- | Get the window's render list node for positioning.
riverWindowV1GetNode :: Ptr RiverWindowV1 -> IO (Ptr RiverNodeV1)
riverWindowV1GetNode = river_window_v1_get_node

foreign import capi "river-window-management-v1.h river_window_v1_get_node"
  river_window_v1_get_node :: Ptr RiverWindowV1 -> IO (Ptr RiverNodeV1)

-- | Propose dimensions for the window.
--
-- Suggests dimensions in the compositor's logical coordinate space.
-- Both width and height must be >= 0.
riverWindowV1ProposeDimensions :: Ptr RiverWindowV1 -> Int -> Int -> IO ()
riverWindowV1ProposeDimensions win w h =
  river_window_v1_propose_dimensions win (fi w) (fi h)

foreign import capi "river-window-management-v1.h river_window_v1_propose_dimensions"
  river_window_v1_propose_dimensions :: Ptr RiverWindowV1 -> CInt -> CInt -> IO ()

-- | Request that the window be hidden.
riverWindowV1Hide :: Ptr RiverWindowV1 -> IO ()
riverWindowV1Hide = river_window_v1_hide

foreign import capi "river-window-management-v1.h river_window_v1_hide"
  river_window_v1_hide :: Ptr RiverWindowV1 -> IO ()

-- | Request that the window be shown.
riverWindowV1Show :: Ptr RiverWindowV1 -> IO ()
riverWindowV1Show = river_window_v1_show

foreign import capi "river-window-management-v1.h river_window_v1_show"
  river_window_v1_show :: Ptr RiverWindowV1 -> IO ()

-- | Tell the client to use client-side decorations (CSD).
riverWindowV1UseCsd :: Ptr RiverWindowV1 -> IO ()
riverWindowV1UseCsd = river_window_v1_use_csd

foreign import capi "river-window-management-v1.h river_window_v1_use_csd"
  river_window_v1_use_csd :: Ptr RiverWindowV1 -> IO ()

-- | Tell the client to use server-side decorations (SSD).
riverWindowV1UseSsd :: Ptr RiverWindowV1 -> IO ()
riverWindowV1UseSsd = river_window_v1_use_ssd

foreign import capi "river-window-management-v1.h river_window_v1_use_ssd"
  river_window_v1_use_ssd :: Ptr RiverWindowV1 -> IO ()

-- | Set window borders.
--
-- Parameters:
--   - @edges@: Bitfield indicating which edges to draw (north, south, east, west)
--   - @width@: Border width in pixels
--   - @color@: Border color as 0xRRGGBBAA
riverWindowV1SetBorders
  :: Ptr RiverWindowV1 -> Word32 -> Int -> Word32 -> IO ()
riverWindowV1SetBorders win edges width color = do
  let r = (color `shiftR` 24) .&. 0xFF
      g = (color `shiftR` 16) .&. 0xFF
      b = (color `shiftR` 8) .&. 0xFF
      a = color .&. 0xFF
  river_window_v1_set_borders win (fi edges) (fi width) (fi r) (fi g) (fi b) (fi a)

foreign import capi "river-window-management-v1.h river_window_v1_set_borders"
  river_window_v1_set_borders
    :: Ptr RiverWindowV1 -> CUInt -> CInt -> CUInt -> CUInt -> CUInt -> CUInt -> IO ()

-- | Set the window's tiled state.
--
-- The @edges@ parameter is a bitfield indicating which edges are tiled
-- (similar to the borders request).
riverWindowV1SetTiled :: Ptr RiverWindowV1 -> Word32 -> IO ()
riverWindowV1SetTiled win edges = river_window_v1_set_tiled win (fi edges)

foreign import capi "river-window-management-v1.h river_window_v1_set_tiled"
  river_window_v1_set_tiled :: Ptr RiverWindowV1 -> CUInt -> IO ()

-- | Create a decoration surface above the window in z-order.
--
-- Assigns the @river_decoration_v1@ role to the surface.
-- Used for titlebar and other UI elements rendered above the window.
riverWindowV1GetDecorationAbove
  :: Ptr RiverWindowV1 -> Ptr WlSurface -> IO (Ptr RiverDecorationV1)
riverWindowV1GetDecorationAbove = river_window_v1_get_decoration_above

foreign import capi "river-window-management-v1.h river_window_v1_get_decoration_above"
  river_window_v1_get_decoration_above
    :: Ptr RiverWindowV1 -> Ptr WlSurface -> IO (Ptr RiverDecorationV1)

-- | Create a decoration surface below the window in z-order.
--
-- Assigns the @river_decoration_v1@ role to the surface.
-- Used for shadows and other UI elements rendered below the window.
riverWindowV1GetDecorationBelow
  :: Ptr RiverWindowV1 -> Ptr WlSurface -> IO (Ptr RiverDecorationV1)
riverWindowV1GetDecorationBelow = river_window_v1_get_decoration_below

foreign import capi "river-window-management-v1.h river_window_v1_get_decoration_below"
  river_window_v1_get_decoration_below
    :: Ptr RiverWindowV1 -> Ptr WlSurface -> IO (Ptr RiverDecorationV1)

-- | Inform the window that it is being resized.
--
-- Called when a resize operation starts (e.g., via pointer drag).
riverWindowV1InformResizeStart :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformResizeStart = river_window_v1_inform_resize_start

foreign import capi "river-window-management-v1.h river_window_v1_inform_resize_start"
  river_window_v1_inform_resize_start :: Ptr RiverWindowV1 -> IO ()

-- | Inform the window that the resize operation has ended.
riverWindowV1InformResizeEnd :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformResizeEnd = river_window_v1_inform_resize_end

foreign import capi "river-window-management-v1.h river_window_v1_inform_resize_end"
  river_window_v1_inform_resize_end :: Ptr RiverWindowV1 -> IO ()

-- | Inform the window of supported window manager capabilities.
--
-- The @caps@ parameter is a bitfield indicating which window manager
-- capabilities the current layout/configuration supports.
riverWindowV1SetCapabilities :: Ptr RiverWindowV1 -> Word32 -> IO ()
riverWindowV1SetCapabilities win caps = river_window_v1_set_capabilities win (fi caps)

foreign import capi "river-window-management-v1.h river_window_v1_set_capabilities"
  river_window_v1_set_capabilities :: Ptr RiverWindowV1 -> CUInt -> IO ()

-- | Inform the window that it is maximized.
riverWindowV1InformMaximized :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformMaximized = river_window_v1_inform_maximized

foreign import capi "river-window-management-v1.h river_window_v1_inform_maximized"
  river_window_v1_inform_maximized :: Ptr RiverWindowV1 -> IO ()

-- | Inform the window that it is unmaximized.
riverWindowV1InformUnmaximized :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformUnmaximized = river_window_v1_inform_unmaximized

foreign import capi "river-window-management-v1.h river_window_v1_inform_unmaximized"
  river_window_v1_inform_unmaximized :: Ptr RiverWindowV1 -> IO ()

riverWindowV1InformFullscreen :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformFullscreen = river_window_v1_inform_fullscreen

foreign import capi "river-window-management-v1.h river_window_v1_inform_fullscreen"
  river_window_v1_inform_fullscreen :: Ptr RiverWindowV1 -> IO ()

riverWindowV1InformNotFullscreen :: Ptr RiverWindowV1 -> IO ()
riverWindowV1InformNotFullscreen = river_window_v1_inform_not_fullscreen

foreign import capi "river-window-management-v1.h river_window_v1_inform_not_fullscreen"
  river_window_v1_inform_not_fullscreen :: Ptr RiverWindowV1 -> IO ()

riverWindowV1Fullscreen :: Ptr RiverWindowV1 -> Ptr RiverOutputV1 -> IO ()
riverWindowV1Fullscreen = river_window_v1_fullscreen

foreign import capi "river-window-management-v1.h river_window_v1_fullscreen"
  river_window_v1_fullscreen :: Ptr RiverWindowV1 -> Ptr RiverOutputV1 -> IO ()

riverWindowV1ExitFullscreen :: Ptr RiverWindowV1 -> IO ()
riverWindowV1ExitFullscreen = river_window_v1_exit_fullscreen

foreign import capi "river-window-management-v1.h river_window_v1_exit_fullscreen"
  river_window_v1_exit_fullscreen :: Ptr RiverWindowV1 -> IO ()

riverWindowV1SetClipBox :: Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
riverWindowV1SetClipBox win x y w h =
  river_window_v1_set_clip_box win (fi x) (fi y) (fi w) (fi h)

foreign import capi "river-window-management-v1.h river_window_v1_set_clip_box"
  river_window_v1_set_clip_box :: Ptr RiverWindowV1 -> CInt -> CInt -> CInt -> CInt -> IO ()

riverWindowV1SetContentClipBox :: Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
riverWindowV1SetContentClipBox win x y w h =
  river_window_v1_set_content_clip_box win (fi x) (fi y) (fi w) (fi h)

foreign import capi "river-window-management-v1.h river_window_v1_set_content_clip_box"
  river_window_v1_set_content_clip_box :: Ptr RiverWindowV1 -> CInt -> CInt -> CInt -> CInt -> IO ()

riverWindowV1SetDimensionBounds :: Ptr RiverWindowV1 -> Int -> Int -> IO ()
riverWindowV1SetDimensionBounds win maxW maxH =
  river_window_v1_set_dimension_bounds win (fi maxW) (fi maxH)

foreign import capi "river-window-management-v1.h river_window_v1_set_dimension_bounds"
  river_window_v1_set_dimension_bounds :: Ptr RiverWindowV1 -> CInt -> CInt -> IO ()

----- window events

type RawWinClosed              = Ptr () -> Ptr RiverWindowV1 -> IO ()
type RawWinDimensionsHint      = Ptr () -> Ptr RiverWindowV1 -> CInt -> CInt -> CInt -> CInt -> IO ()
type RawWinDimensions          = Ptr () -> Ptr RiverWindowV1 -> CInt -> CInt -> IO ()
type RawWinAppId               = Ptr () -> Ptr RiverWindowV1 -> CString -> IO ()
type RawWinTitle               = Ptr () -> Ptr RiverWindowV1 -> CString -> IO ()
type RawWinParent              = Ptr () -> Ptr RiverWindowV1 -> Ptr RiverWindowV1 -> IO ()
type RawWinDecorationHint      = Ptr () -> Ptr RiverWindowV1 -> CUInt -> IO ()
type RawWinPointerMoveReq      = Ptr () -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> IO ()
type RawWinPointerResizeReq    = Ptr () -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> CUInt -> IO ()
type RawWinShowMenuReq         = Ptr () -> Ptr RiverWindowV1 -> CInt -> CInt -> IO ()
type RawWinMaximizeReq         = Ptr () -> Ptr RiverWindowV1 -> IO ()
type RawWinUnmaximizeReq       = Ptr () -> Ptr RiverWindowV1 -> IO ()
type RawWinFullscreenReq       = Ptr () -> Ptr RiverWindowV1 -> Ptr RiverOutputV1 -> IO ()
type RawWinExitFullscreenReq   = Ptr () -> Ptr RiverWindowV1 -> IO ()
type RawWinMinimizeReq         = Ptr () -> Ptr RiverWindowV1 -> IO ()
type RawWinUnreliablePid       = Ptr () -> Ptr RiverWindowV1 -> CInt -> IO ()
type RawWinPresentationHint    = Ptr () -> Ptr RiverWindowV1 -> CUInt -> IO ()
type RawWinIdentifier          = Ptr () -> Ptr RiverWindowV1 -> CString -> IO ()

foreign import ccall "wrapper" mkRawWinClosed            :: RawWinClosed            -> IO (FunPtr RawWinClosed)
foreign import ccall "wrapper" mkRawWinDimensionsHint    :: RawWinDimensionsHint    -> IO (FunPtr RawWinDimensionsHint)
foreign import ccall "wrapper" mkRawWinDimensions        :: RawWinDimensions        -> IO (FunPtr RawWinDimensions)
foreign import ccall "wrapper" mkRawWinAppId             :: RawWinAppId             -> IO (FunPtr RawWinAppId)
foreign import ccall "wrapper" mkRawWinTitle             :: RawWinTitle             -> IO (FunPtr RawWinTitle)
foreign import ccall "wrapper" mkRawWinParent            :: RawWinParent            -> IO (FunPtr RawWinParent)
foreign import ccall "wrapper" mkRawWinDecorationHint    :: RawWinDecorationHint    -> IO (FunPtr RawWinDecorationHint)
foreign import ccall "wrapper" mkRawWinPointerMoveReq    :: RawWinPointerMoveReq    -> IO (FunPtr RawWinPointerMoveReq)
foreign import ccall "wrapper" mkRawWinPointerResizeReq  :: RawWinPointerResizeReq  -> IO (FunPtr RawWinPointerResizeReq)
foreign import ccall "wrapper" mkRawWinShowMenuReq       :: RawWinShowMenuReq       -> IO (FunPtr RawWinShowMenuReq)
foreign import ccall "wrapper" mkRawWinMaximizeReq       :: RawWinMaximizeReq       -> IO (FunPtr RawWinMaximizeReq)
foreign import ccall "wrapper" mkRawWinUnmaximizeReq     :: RawWinUnmaximizeReq     -> IO (FunPtr RawWinUnmaximizeReq)
foreign import ccall "wrapper" mkRawWinFullscreenReq     :: RawWinFullscreenReq     -> IO (FunPtr RawWinFullscreenReq)
foreign import ccall "wrapper" mkRawWinExitFullscreenReq :: RawWinExitFullscreenReq -> IO (FunPtr RawWinExitFullscreenReq)
foreign import ccall "wrapper" mkRawWinMinimizeReq       :: RawWinMinimizeReq       -> IO (FunPtr RawWinMinimizeReq)
foreign import ccall "wrapper" mkRawWinUnreliablePid     :: RawWinUnreliablePid     -> IO (FunPtr RawWinUnreliablePid)
foreign import ccall "wrapper" mkRawWinPresentationHint  :: RawWinPresentationHint  -> IO (FunPtr RawWinPresentationHint)
foreign import ccall "wrapper" mkRawWinIdentifier        :: RawWinIdentifier        -> IO (FunPtr RawWinIdentifier)

data WindowListener = WindowListener
  { onWinClosed            :: Ptr RiverWindowV1 -> IO ()
  , onWinDimensionsHint    :: Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
  , onWinDimensions        :: Ptr RiverWindowV1 -> Int -> Int -> IO ()
  , onWinAppId             :: Ptr RiverWindowV1 -> Maybe String -> IO ()
  , onWinTitle             :: Ptr RiverWindowV1 -> Maybe String -> IO ()
  , onWinParent            :: Ptr RiverWindowV1 -> Maybe (Ptr RiverWindowV1) -> IO ()
  , onWinDecorationHint    :: Ptr RiverWindowV1 -> Word32 -> IO ()
  , onWinPointerMoveReq    :: Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> IO ()
  , onWinPointerResizeReq  :: Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> Word32 -> IO ()
  , onWinShowMenuReq       :: Ptr RiverWindowV1 -> Int -> Int -> IO ()
  , onWinMaximizeReq       :: Ptr RiverWindowV1 -> IO ()
  , onWinUnmaximizeReq     :: Ptr RiverWindowV1 -> IO ()
  , onWinFullscreenReq     :: Ptr RiverWindowV1 -> Maybe (Ptr RiverOutputV1) -> IO ()
  , onWinExitFullscreenReq :: Ptr RiverWindowV1 -> IO ()
  , onWinMinimizeReq       :: Ptr RiverWindowV1 -> IO ()
  , onWinUnreliablePid     :: Ptr RiverWindowV1 -> Int -> IO ()
  , onWinPresentationHint  :: Ptr RiverWindowV1 -> Word32 -> IO ()
  , onWinIdentifier        :: Ptr RiverWindowV1 -> String -> IO ()
  }

riverWindowV1AddListener :: Ptr RiverWindowV1 -> WindowListener -> IO (IO ())
riverWindowV1AddListener win WindowListener{..} = do
  fp0  <- mkRawWinClosed            $ \_  w             -> onWinClosed w
  fp1  <- mkRawWinDimensionsHint    $ \_  w mn mh xx xh -> onWinDimensionsHint w (fi mn) (fi mh) (fi xx) (fi xh)
  fp2  <- mkRawWinDimensions        $ \_  w wd h        -> onWinDimensions w (fi wd) (fi h)
  fp3  <- mkRawWinAppId             $ \_  w cs          -> nullableStr cs >>= onWinAppId w
  fp4  <- mkRawWinTitle             $ \_  w cs          -> nullableStr cs >>= onWinTitle w
  fp5  <- mkRawWinParent            $ \_  w p           -> onWinParent w (nullablePtr p)
  fp6  <- mkRawWinDecorationHint    $ \_  w h           -> onWinDecorationHint w (fi h)
  fp7  <- mkRawWinPointerMoveReq    $ \_  w s           -> onWinPointerMoveReq w s
  fp8  <- mkRawWinPointerResizeReq  $ \_  w s e         -> onWinPointerResizeReq w s (fi e)
  fp9  <- mkRawWinShowMenuReq       $ \_  w x y         -> onWinShowMenuReq w (fi x) (fi y)
  fp10 <- mkRawWinMaximizeReq       $ \_  w             -> onWinMaximizeReq w
  fp11 <- mkRawWinUnmaximizeReq     $ \_  w             -> onWinUnmaximizeReq w
  fp12 <- mkRawWinFullscreenReq     $ \_  w o           -> onWinFullscreenReq w (nullablePtr o)
  fp13 <- mkRawWinExitFullscreenReq $ \_  w             -> onWinExitFullscreenReq w
  fp14 <- mkRawWinMinimizeReq       $ \_  w             -> onWinMinimizeReq w
  fp15 <- mkRawWinUnreliablePid     $ \_  w p           -> onWinUnreliablePid w (fi p)
  fp16 <- mkRawWinPresentationHint  $ \_  w h           -> onWinPresentationHint w (fi h)
  fp17 <- mkRawWinIdentifier        $ \_  w cs          -> peekCString cs >>= onWinIdentifier w
  lp <- newArray
    [ castFunPtr fp0,  castFunPtr fp1,  castFunPtr fp2,  castFunPtr fp3
    , castFunPtr fp4,  castFunPtr fp5,  castFunPtr fp6,  castFunPtr fp7
    , castFunPtr fp8,  castFunPtr fp9,  castFunPtr fp10, castFunPtr fp11
    , castFunPtr fp12, castFunPtr fp13, castFunPtr fp14, castFunPtr fp15
    , castFunPtr fp16, castFunPtr fp17 :: FunPtr (IO ()) ]
  _ <- wl_proxy_add_listener (castPtr win) lp nullPtr
  pure $ do
    mapM_ freeHaskellFunPtr
      [ castFunPtr fp0,  castFunPtr fp1,  castFunPtr fp2,  castFunPtr fp3
      , castFunPtr fp4,  castFunPtr fp5,  castFunPtr fp6,  castFunPtr fp7
      , castFunPtr fp8,  castFunPtr fp9,  castFunPtr fp10, castFunPtr fp11
      , castFunPtr fp12, castFunPtr fp13, castFunPtr fp14, castFunPtr fp15
      , castFunPtr fp16, castFunPtr fp17 :: FunPtr (IO ()) ]
    free lp

----- decoration requests (no events)

riverDecorationV1Destroy :: Ptr RiverDecorationV1 -> IO ()
riverDecorationV1Destroy = river_decoration_v1_destroy

foreign import capi "river-window-management-v1.h river_decoration_v1_destroy"
  river_decoration_v1_destroy :: Ptr RiverDecorationV1 -> IO ()

riverDecorationV1SetOffset :: Ptr RiverDecorationV1 -> Int -> Int -> IO ()
riverDecorationV1SetOffset dec x y = river_decoration_v1_set_offset dec (fi x) (fi y)

foreign import capi "river-window-management-v1.h river_decoration_v1_set_offset"
  river_decoration_v1_set_offset :: Ptr RiverDecorationV1 -> CInt -> CInt -> IO ()

riverDecorationV1SyncNextCommit :: Ptr RiverDecorationV1 -> IO ()
riverDecorationV1SyncNextCommit = river_decoration_v1_sync_next_commit

foreign import capi "river-window-management-v1.h river_decoration_v1_sync_next_commit"
  river_decoration_v1_sync_next_commit :: Ptr RiverDecorationV1 -> IO ()

----- shell surface requests (no events)

riverShellSurfaceV1Destroy :: Ptr RiverShellSurfaceV1 -> IO ()
riverShellSurfaceV1Destroy = river_shell_surface_v1_destroy

foreign import capi "river-window-management-v1.h river_shell_surface_v1_destroy"
  river_shell_surface_v1_destroy :: Ptr RiverShellSurfaceV1 -> IO ()

riverShellSurfaceV1GetNode :: Ptr RiverShellSurfaceV1 -> IO (Ptr RiverNodeV1)
riverShellSurfaceV1GetNode = river_shell_surface_v1_get_node

foreign import capi "river-window-management-v1.h river_shell_surface_v1_get_node"
  river_shell_surface_v1_get_node :: Ptr RiverShellSurfaceV1 -> IO (Ptr RiverNodeV1)

riverShellSurfaceV1SyncNextCommit :: Ptr RiverShellSurfaceV1 -> IO ()
riverShellSurfaceV1SyncNextCommit = river_shell_surface_v1_sync_next_commit

foreign import capi "river-window-management-v1.h river_shell_surface_v1_sync_next_commit"
  river_shell_surface_v1_sync_next_commit :: Ptr RiverShellSurfaceV1 -> IO ()

----- node requests (no events)

riverNodeV1Destroy :: Ptr RiverNodeV1 -> IO ()
riverNodeV1Destroy = river_node_v1_destroy

foreign import capi "river-window-management-v1.h river_node_v1_destroy"
  river_node_v1_destroy :: Ptr RiverNodeV1 -> IO ()

riverNodeV1SetPosition :: Ptr RiverNodeV1 -> Int -> Int -> IO ()
riverNodeV1SetPosition node x y = river_node_v1_set_position node (fi x) (fi y)

foreign import capi "river-window-management-v1.h river_node_v1_set_position"
  river_node_v1_set_position :: Ptr RiverNodeV1 -> CInt -> CInt -> IO ()

riverNodeV1PlaceTop :: Ptr RiverNodeV1 -> IO ()
riverNodeV1PlaceTop = river_node_v1_place_top

foreign import capi "river-window-management-v1.h river_node_v1_place_top"
  river_node_v1_place_top :: Ptr RiverNodeV1 -> IO ()

riverNodeV1PlaceBottom :: Ptr RiverNodeV1 -> IO ()
riverNodeV1PlaceBottom = river_node_v1_place_bottom

foreign import capi "river-window-management-v1.h river_node_v1_place_bottom"
  river_node_v1_place_bottom :: Ptr RiverNodeV1 -> IO ()

riverNodeV1PlaceAbove :: Ptr RiverNodeV1 -> Ptr RiverNodeV1 -> IO ()
riverNodeV1PlaceAbove = river_node_v1_place_above

foreign import capi "river-window-management-v1.h river_node_v1_place_above"
  river_node_v1_place_above :: Ptr RiverNodeV1 -> Ptr RiverNodeV1 -> IO ()

riverNodeV1PlaceBelow :: Ptr RiverNodeV1 -> Ptr RiverNodeV1 -> IO ()
riverNodeV1PlaceBelow = river_node_v1_place_below

foreign import capi "river-window-management-v1.h river_node_v1_place_below"
  river_node_v1_place_below :: Ptr RiverNodeV1 -> Ptr RiverNodeV1 -> IO ()

-- | Output (display) request and event functions.
-- Outputs represent connected displays managed by the compositor.

----- output requests + events

-- | Destroy the output object.
riverOutputV1Destroy :: Ptr RiverOutputV1 -> IO ()
riverOutputV1Destroy = river_output_v1_destroy

foreign import capi "river-window-management-v1.h river_output_v1_destroy"
  river_output_v1_destroy :: Ptr RiverOutputV1 -> IO ()

-- | Set the preferred presentation mode for the output.
--
-- Specifies how frames should be presented (e.g., VSync, mailbox, immediate).
riverOutputV1SetPresentationMode :: Ptr RiverOutputV1 -> Word32 -> IO ()
riverOutputV1SetPresentationMode out mode =
  river_output_v1_set_presentation_mode out (fi mode)

foreign import capi "river-window-management-v1.h river_output_v1_set_presentation_mode"
  river_output_v1_set_presentation_mode :: Ptr RiverOutputV1 -> CUInt -> IO ()

type RawOutRemoved    = Ptr () -> Ptr RiverOutputV1 -> IO ()
type RawOutWlOutput   = Ptr () -> Ptr RiverOutputV1 -> CUInt -> IO ()
type RawOutPosition   = Ptr () -> Ptr RiverOutputV1 -> CInt -> CInt -> IO ()
type RawOutDimensions = Ptr () -> Ptr RiverOutputV1 -> CInt -> CInt -> IO ()

foreign import ccall "wrapper" mkRawOutRemoved    :: RawOutRemoved    -> IO (FunPtr RawOutRemoved)
foreign import ccall "wrapper" mkRawOutWlOutput   :: RawOutWlOutput   -> IO (FunPtr RawOutWlOutput)
foreign import ccall "wrapper" mkRawOutPosition   :: RawOutPosition   -> IO (FunPtr RawOutPosition)
foreign import ccall "wrapper" mkRawOutDimensions :: RawOutDimensions -> IO (FunPtr RawOutDimensions)

-- | Listener record for output events.
data OutputListener = OutputListener
  { onOutRemoved    :: Ptr RiverOutputV1 -> IO ()
    -- ^ The output has been removed.
  , onOutWlOutput   :: Ptr RiverOutputV1 -> Word32 -> IO ()
    -- ^ The associated wl_output object ID.
  , onOutPosition   :: Ptr RiverOutputV1 -> Int -> Int -> IO ()
    -- ^ Output position in the global coordinate space.
  , onOutDimensions :: Ptr RiverOutputV1 -> Int -> Int -> IO ()
    -- ^ Output dimensions (width, height) in pixels.
  }

riverOutputV1AddListener :: Ptr RiverOutputV1 -> OutputListener -> IO (IO ())
riverOutputV1AddListener out OutputListener{..} = do
  fp0 <- mkRawOutRemoved    $ \_ o     -> onOutRemoved o
  fp1 <- mkRawOutWlOutput   $ \_ o n   -> onOutWlOutput o (fi n)
  fp2 <- mkRawOutPosition   $ \_ o x y -> onOutPosition o (fi x) (fi y)
  fp3 <- mkRawOutDimensions $ \_ o w h -> onOutDimensions o (fi w) (fi h)
  lp  <- newArray [castFunPtr fp0, castFunPtr fp1, castFunPtr fp2, castFunPtr fp3 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr out) lp nullPtr
  pure $ do
    freeHaskellFunPtr fp0
    freeHaskellFunPtr fp1
    freeHaskellFunPtr fp2
    freeHaskellFunPtr fp3
    free lp

-- | Seat (input device collection) request and event functions.
-- A seat represents a collection of input devices (keyboard, pointer, touch).

----- seat requests + events

-- | Destroy the seat object.
riverSeatV1Destroy :: Ptr RiverSeatV1 -> IO ()
riverSeatV1Destroy = river_seat_v1_destroy

foreign import capi "river-window-management-v1.h river_seat_v1_destroy"
  river_seat_v1_destroy :: Ptr RiverSeatV1 -> IO ()

-- | Give keyboard focus to a window.
--
-- Directs keyboard input to the specified window.
riverSeatV1FocusWindow :: Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
riverSeatV1FocusWindow = river_seat_v1_focus_window

foreign import capi "river-window-management-v1.h river_seat_v1_focus_window"
  river_seat_v1_focus_window :: Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()

-- | Give keyboard focus to a shell surface (window manager UI).
--
-- Directs keyboard input to the specified shell surface.
riverSeatV1FocusShellSurface :: Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
riverSeatV1FocusShellSurface = river_seat_v1_focus_shell_surface

foreign import capi "river-window-management-v1.h river_seat_v1_focus_shell_surface"
  river_seat_v1_focus_shell_surface :: Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()

-- | Clear keyboard focus.
--
-- No surface will receive keyboard input until focus is restored.
riverSeatV1ClearFocus :: Ptr RiverSeatV1 -> IO ()
riverSeatV1ClearFocus = river_seat_v1_clear_focus

foreign import capi "river-window-management-v1.h river_seat_v1_clear_focus"
  river_seat_v1_clear_focus :: Ptr RiverSeatV1 -> IO ()

-- | Start an interactive pointer operation.
--
-- Initiates a pointer-driven interaction mode (e.g., window drag/resize).
riverSeatV1OpStartPointer :: Ptr RiverSeatV1 -> IO ()
riverSeatV1OpStartPointer = river_seat_v1_op_start_pointer

foreign import capi "river-window-management-v1.h river_seat_v1_op_start_pointer"
  river_seat_v1_op_start_pointer :: Ptr RiverSeatV1 -> IO ()

-- | End an interactive operation.
--
-- Terminates the current pointer or keyboard interactive operation.
riverSeatV1OpEnd :: Ptr RiverSeatV1 -> IO ()
riverSeatV1OpEnd = river_seat_v1_op_end

foreign import capi "river-window-management-v1.h river_seat_v1_op_end"
  river_seat_v1_op_end :: Ptr RiverSeatV1 -> IO ()

-- | Define a new pointer binding (button + modifier combination).
--
-- Creates a binding for a specific mouse button with optional modifiers.
-- Returns a 'RiverPointerBindingV1' for managing the binding.
riverSeatV1GetPointerBinding
  :: Ptr RiverSeatV1 -> Word32 -> Word32 -> IO (Ptr RiverPointerBindingV1)
riverSeatV1GetPointerBinding seat btn mods =
  river_seat_v1_get_pointer_binding seat (fi btn) (fi mods)

foreign import capi "river-window-management-v1.h river_seat_v1_get_pointer_binding"
  river_seat_v1_get_pointer_binding
    :: Ptr RiverSeatV1 -> CUInt -> CUInt -> IO (Ptr RiverPointerBindingV1)

-- | Set the XCursor theme for this seat.
--
-- Configures the visual cursor theme and size (in pixels).
riverSeatV1SetXcursorTheme :: Ptr RiverSeatV1 -> String -> Word32 -> IO ()
riverSeatV1SetXcursorTheme seat name size =
  withCString name $ \cs -> river_seat_v1_set_xcursor_theme seat cs (fi size)

foreign import capi "river-window-management-v1.h river_seat_v1_set_xcursor_theme"
  river_seat_v1_set_xcursor_theme :: Ptr RiverSeatV1 -> CString -> CUInt -> IO ()

riverSeatV1PointerWarp :: Ptr RiverSeatV1 -> Int -> Int -> IO ()
riverSeatV1PointerWarp seat x y = river_seat_v1_pointer_warp seat (fi x) (fi y)

foreign import capi "river-window-management-v1.h river_seat_v1_pointer_warp"
  river_seat_v1_pointer_warp :: Ptr RiverSeatV1 -> CInt -> CInt -> IO ()

type RawSeatRemoved             = Ptr () -> Ptr RiverSeatV1 -> IO ()
type RawSeatWlSeat              = Ptr () -> Ptr RiverSeatV1 -> CUInt -> IO ()
type RawSeatPointerEnter        = Ptr () -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
type RawSeatPointerLeave        = Ptr () -> Ptr RiverSeatV1 -> IO ()
type RawSeatWindowInteraction   = Ptr () -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
type RawSeatShellInteraction    = Ptr () -> Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
type RawSeatOpDelta             = Ptr () -> Ptr RiverSeatV1 -> CInt -> CInt -> IO ()
type RawSeatOpRelease           = Ptr () -> Ptr RiverSeatV1 -> IO ()
type RawSeatPointerPosition     = Ptr () -> Ptr RiverSeatV1 -> CInt -> CInt -> IO ()

foreign import ccall "wrapper" mkRawSeatRemoved           :: RawSeatRemoved           -> IO (FunPtr RawSeatRemoved)
foreign import ccall "wrapper" mkRawSeatWlSeat            :: RawSeatWlSeat            -> IO (FunPtr RawSeatWlSeat)
foreign import ccall "wrapper" mkRawSeatPointerEnter      :: RawSeatPointerEnter      -> IO (FunPtr RawSeatPointerEnter)
foreign import ccall "wrapper" mkRawSeatPointerLeave      :: RawSeatPointerLeave      -> IO (FunPtr RawSeatPointerLeave)
foreign import ccall "wrapper" mkRawSeatWindowInteraction :: RawSeatWindowInteraction -> IO (FunPtr RawSeatWindowInteraction)
foreign import ccall "wrapper" mkRawSeatShellInteraction  :: RawSeatShellInteraction  -> IO (FunPtr RawSeatShellInteraction)
foreign import ccall "wrapper" mkRawSeatOpDelta           :: RawSeatOpDelta           -> IO (FunPtr RawSeatOpDelta)
foreign import ccall "wrapper" mkRawSeatOpRelease         :: RawSeatOpRelease         -> IO (FunPtr RawSeatOpRelease)
foreign import ccall "wrapper" mkRawSeatPointerPosition   :: RawSeatPointerPosition   -> IO (FunPtr RawSeatPointerPosition)

data SeatListener = SeatListener
  { onSeatRemoved           :: Ptr RiverSeatV1 -> IO ()
  , onSeatWlSeat            :: Ptr RiverSeatV1 -> Word32 -> IO ()
  , onSeatPointerEnter      :: Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
  , onSeatPointerLeave      :: Ptr RiverSeatV1 -> IO ()
  , onSeatWindowInteraction :: Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
  , onSeatShellInteraction  :: Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
  , onSeatOpDelta           :: Ptr RiverSeatV1 -> Int -> Int -> IO ()
  , onSeatOpRelease         :: Ptr RiverSeatV1 -> IO ()
  , onSeatPointerPosition   :: Ptr RiverSeatV1 -> Int -> Int -> IO ()
  }

riverSeatV1AddListener :: Ptr RiverSeatV1 -> SeatListener -> IO (IO ())
riverSeatV1AddListener seat SeatListener{..} = do
  fp0 <- mkRawSeatRemoved           $ \_ s     -> onSeatRemoved s
  fp1 <- mkRawSeatWlSeat            $ \_ s n   -> onSeatWlSeat s (fi n)
  fp2 <- mkRawSeatPointerEnter      $ \_ s w   -> onSeatPointerEnter s w
  fp3 <- mkRawSeatPointerLeave      $ \_ s     -> onSeatPointerLeave s
  fp4 <- mkRawSeatWindowInteraction $ \_ s w   -> onSeatWindowInteraction s w
  fp5 <- mkRawSeatShellInteraction  $ \_ s ss  -> onSeatShellInteraction s ss
  fp6 <- mkRawSeatOpDelta           $ \_ s x y -> onSeatOpDelta s (fi x) (fi y)
  fp7 <- mkRawSeatOpRelease         $ \_ s     -> onSeatOpRelease s
  fp8 <- mkRawSeatPointerPosition   $ \_ s x y -> onSeatPointerPosition s (fi x) (fi y)
  lp  <- newArray
    [ castFunPtr fp0, castFunPtr fp1, castFunPtr fp2
    , castFunPtr fp3, castFunPtr fp4, castFunPtr fp5
    , castFunPtr fp6, castFunPtr fp7, castFunPtr fp8 :: FunPtr (IO ()) ]
  _ <- wl_proxy_add_listener (castPtr seat) lp nullPtr
  pure $ do
    mapM_ freeHaskellFunPtr
      [ castFunPtr fp0, castFunPtr fp1, castFunPtr fp2
      , castFunPtr fp3, castFunPtr fp4, castFunPtr fp5
      , castFunPtr fp6, castFunPtr fp7, castFunPtr fp8 :: FunPtr (IO ()) ]
    free lp

----- pointer binding

riverPointerBindingV1Destroy :: Ptr RiverPointerBindingV1 -> IO ()
riverPointerBindingV1Destroy = river_pointer_binding_v1_destroy

foreign import capi "river-window-management-v1.h river_pointer_binding_v1_destroy"
  river_pointer_binding_v1_destroy :: Ptr RiverPointerBindingV1 -> IO ()

riverPointerBindingV1Enable :: Ptr RiverPointerBindingV1 -> IO ()
riverPointerBindingV1Enable = river_pointer_binding_v1_enable

foreign import capi "river-window-management-v1.h river_pointer_binding_v1_enable"
  river_pointer_binding_v1_enable :: Ptr RiverPointerBindingV1 -> IO ()

riverPointerBindingV1Disable :: Ptr RiverPointerBindingV1 -> IO ()
riverPointerBindingV1Disable = river_pointer_binding_v1_disable

foreign import capi "river-window-management-v1.h river_pointer_binding_v1_disable"
  river_pointer_binding_v1_disable :: Ptr RiverPointerBindingV1 -> IO ()

type RawPbPressed  = Ptr () -> Ptr RiverPointerBindingV1 -> IO ()
type RawPbReleased = Ptr () -> Ptr RiverPointerBindingV1 -> IO ()

foreign import ccall "wrapper" mkRawPbPressed  :: RawPbPressed  -> IO (FunPtr RawPbPressed)
foreign import ccall "wrapper" mkRawPbReleased :: RawPbReleased -> IO (FunPtr RawPbReleased)

data PointerBindingListener = PointerBindingListener
  { onPbPressed  :: Ptr RiverPointerBindingV1 -> IO ()
  , onPbReleased :: Ptr RiverPointerBindingV1 -> IO ()
  }

riverPointerBindingV1AddListener
  :: Ptr RiverPointerBindingV1 -> PointerBindingListener -> IO (IO ())
riverPointerBindingV1AddListener pb PointerBindingListener{..} = do
  fp0 <- mkRawPbPressed  $ \_ b -> onPbPressed b
  fp1 <- mkRawPbReleased $ \_ b -> onPbReleased b
  lp  <- newArray [castFunPtr fp0, castFunPtr fp1 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr pb) lp nullPtr
  pure $ do
    freeHaskellFunPtr fp0
    freeHaskellFunPtr fp1
    free lp

----- xkb bindings manager

riverXkbBindingsV1Destroy :: Ptr RiverXkbBindingsV1 -> IO ()
riverXkbBindingsV1Destroy = river_xkb_bindings_v1_destroy

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_v1_destroy"
  river_xkb_bindings_v1_destroy :: Ptr RiverXkbBindingsV1 -> IO ()

riverXkbBindingsV1GetXkbBinding
  :: Ptr RiverXkbBindingsV1 -> Ptr RiverSeatV1 -> Word32 -> Word32
  -> IO (Ptr RiverXkbBindingV1)
riverXkbBindingsV1GetXkbBinding xkb seat keysym mods =
  river_xkb_bindings_v1_get_xkb_binding xkb seat (fi keysym) (fi mods)

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_v1_get_xkb_binding"
  river_xkb_bindings_v1_get_xkb_binding
    :: Ptr RiverXkbBindingsV1 -> Ptr RiverSeatV1 -> CUInt -> CUInt
    -> IO (Ptr RiverXkbBindingV1)

riverXkbBindingsV1GetSeat
  :: Ptr RiverXkbBindingsV1 -> Ptr RiverSeatV1 -> IO (Ptr RiverXkbBindingsSeatV1)
riverXkbBindingsV1GetSeat = river_xkb_bindings_v1_get_seat

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_v1_get_seat"
  river_xkb_bindings_v1_get_seat
    :: Ptr RiverXkbBindingsV1 -> Ptr RiverSeatV1 -> IO (Ptr RiverXkbBindingsSeatV1)

----- xkb binding

riverXkbBindingV1Destroy :: Ptr RiverXkbBindingV1 -> IO ()
riverXkbBindingV1Destroy = river_xkb_binding_v1_destroy

foreign import capi "river-xkb-bindings-v1.h river_xkb_binding_v1_destroy"
  river_xkb_binding_v1_destroy :: Ptr RiverXkbBindingV1 -> IO ()

riverXkbBindingV1SetLayoutOverride :: Ptr RiverXkbBindingV1 -> Word32 -> IO ()
riverXkbBindingV1SetLayoutOverride b layout =
  river_xkb_binding_v1_set_layout_override b (fi layout)

foreign import capi "river-xkb-bindings-v1.h river_xkb_binding_v1_set_layout_override"
  river_xkb_binding_v1_set_layout_override :: Ptr RiverXkbBindingV1 -> CUInt -> IO ()

riverXkbBindingV1Enable :: Ptr RiverXkbBindingV1 -> IO ()
riverXkbBindingV1Enable = river_xkb_binding_v1_enable

foreign import capi "river-xkb-bindings-v1.h river_xkb_binding_v1_enable"
  river_xkb_binding_v1_enable :: Ptr RiverXkbBindingV1 -> IO ()

riverXkbBindingV1Disable :: Ptr RiverXkbBindingV1 -> IO ()
riverXkbBindingV1Disable = river_xkb_binding_v1_disable

foreign import capi "river-xkb-bindings-v1.h river_xkb_binding_v1_disable"
  river_xkb_binding_v1_disable :: Ptr RiverXkbBindingV1 -> IO ()

type RawXkbPressed    = Ptr () -> Ptr RiverXkbBindingV1 -> IO ()
type RawXkbReleased   = Ptr () -> Ptr RiverXkbBindingV1 -> IO ()
type RawXkbStopRepeat = Ptr () -> Ptr RiverXkbBindingV1 -> IO ()

foreign import ccall "wrapper" mkRawXkbPressed    :: RawXkbPressed    -> IO (FunPtr RawXkbPressed)
foreign import ccall "wrapper" mkRawXkbReleased   :: RawXkbReleased   -> IO (FunPtr RawXkbReleased)
foreign import ccall "wrapper" mkRawXkbStopRepeat :: RawXkbStopRepeat -> IO (FunPtr RawXkbStopRepeat)

data XkbBindingListener = XkbBindingListener
  { onXkbPressed    :: Ptr RiverXkbBindingV1 -> IO ()
  , onXkbReleased   :: Ptr RiverXkbBindingV1 -> IO ()
  , onXkbStopRepeat :: Ptr RiverXkbBindingV1 -> IO ()
  }

riverXkbBindingV1AddListener :: Ptr RiverXkbBindingV1 -> XkbBindingListener -> IO (IO ())
riverXkbBindingV1AddListener b XkbBindingListener{..} = do
  fp0 <- mkRawXkbPressed    $ \_ x -> onXkbPressed x
  fp1 <- mkRawXkbReleased   $ \_ x -> onXkbReleased x
  fp2 <- mkRawXkbStopRepeat $ \_ x -> onXkbStopRepeat x
  lp  <- newArray [castFunPtr fp0, castFunPtr fp1, castFunPtr fp2 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr b) lp nullPtr
  pure $ do
    freeHaskellFunPtr fp0
    freeHaskellFunPtr fp1
    freeHaskellFunPtr fp2
    free lp

----- xkb bindings seat

riverXkbBindingsSeatV1Destroy :: Ptr RiverXkbBindingsSeatV1 -> IO ()
riverXkbBindingsSeatV1Destroy = river_xkb_bindings_seat_v1_destroy

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_seat_v1_destroy"
  river_xkb_bindings_seat_v1_destroy :: Ptr RiverXkbBindingsSeatV1 -> IO ()

riverXkbBindingsSeatV1EnsureNextKeyEaten :: Ptr RiverXkbBindingsSeatV1 -> IO ()
riverXkbBindingsSeatV1EnsureNextKeyEaten = river_xkb_bindings_seat_v1_ensure_next_key_eaten

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_seat_v1_ensure_next_key_eaten"
  river_xkb_bindings_seat_v1_ensure_next_key_eaten :: Ptr RiverXkbBindingsSeatV1 -> IO ()

riverXkbBindingsSeatV1CancelEnsureNextKeyEaten :: Ptr RiverXkbBindingsSeatV1 -> IO ()
riverXkbBindingsSeatV1CancelEnsureNextKeyEaten =
  river_xkb_bindings_seat_v1_cancel_ensure_next_key_eaten

foreign import capi "river-xkb-bindings-v1.h river_xkb_bindings_seat_v1_cancel_ensure_next_key_eaten"
  river_xkb_bindings_seat_v1_cancel_ensure_next_key_eaten :: Ptr RiverXkbBindingsSeatV1 -> IO ()

type RawXkbSeatAteKey = Ptr () -> Ptr RiverXkbBindingsSeatV1 -> IO ()

foreign import ccall "wrapper" mkRawXkbSeatAteKey :: RawXkbSeatAteKey -> IO (FunPtr RawXkbSeatAteKey)

newtype XkbBindingsSeatListener = XkbBindingsSeatListener
  { onXkbSeatAteUnboundKey :: Ptr RiverXkbBindingsSeatV1 -> IO ()
  }

riverXkbBindingsSeatV1AddListener
  :: Ptr RiverXkbBindingsSeatV1 -> XkbBindingsSeatListener -> IO (IO ())
riverXkbBindingsSeatV1AddListener s XkbBindingsSeatListener{..} = do
  fp0 <- mkRawXkbSeatAteKey $ \_ x -> onXkbSeatAteUnboundKey x
  lp  <- newArray [castFunPtr fp0 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr s) lp nullPtr
  pure $ freeHaskellFunPtr fp0 >> free lp

----- input manager

riverInputManagerV1Stop :: Ptr RiverInputManagerV1 -> IO ()
riverInputManagerV1Stop = river_input_manager_v1_stop

foreign import capi "river-input-management-v1.h river_input_manager_v1_stop"
  river_input_manager_v1_stop :: Ptr RiverInputManagerV1 -> IO ()

riverInputManagerV1Destroy :: Ptr RiverInputManagerV1 -> IO ()
riverInputManagerV1Destroy = river_input_manager_v1_destroy

foreign import capi "river-input-management-v1.h river_input_manager_v1_destroy"
  river_input_manager_v1_destroy :: Ptr RiverInputManagerV1 -> IO ()

riverInputManagerV1CreateSeat :: Ptr RiverInputManagerV1 -> String -> IO ()
riverInputManagerV1CreateSeat mgr name =
  withCString name $ river_input_manager_v1_create_seat mgr

foreign import capi "river-input-management-v1.h river_input_manager_v1_create_seat"
  river_input_manager_v1_create_seat :: Ptr RiverInputManagerV1 -> CString -> IO ()

riverInputManagerV1DestroySeat :: Ptr RiverInputManagerV1 -> String -> IO ()
riverInputManagerV1DestroySeat mgr name =
  withCString name $ river_input_manager_v1_destroy_seat mgr

foreign import capi "river-input-management-v1.h river_input_manager_v1_destroy_seat"
  river_input_manager_v1_destroy_seat :: Ptr RiverInputManagerV1 -> CString -> IO ()

type RawImFinished    = Ptr () -> Ptr RiverInputManagerV1 -> IO ()
type RawImInputDevice = Ptr () -> Ptr RiverInputManagerV1 -> Ptr RiverInputDeviceV1 -> IO ()

foreign import ccall "wrapper" mkRawImFinished    :: RawImFinished    -> IO (FunPtr RawImFinished)
foreign import ccall "wrapper" mkRawImInputDevice :: RawImInputDevice -> IO (FunPtr RawImInputDevice)

data InputManagerListener = InputManagerListener
  { onImFinished    :: Ptr RiverInputManagerV1 -> IO ()
  , onImInputDevice :: Ptr RiverInputManagerV1 -> Ptr RiverInputDeviceV1 -> IO ()
  }

riverInputManagerV1AddListener
  :: Ptr RiverInputManagerV1 -> InputManagerListener -> IO (IO ())
riverInputManagerV1AddListener mgr InputManagerListener{..} = do
  fp0 <- mkRawImFinished    $ \_ m   -> onImFinished m
  fp1 <- mkRawImInputDevice $ \_ m d -> onImInputDevice m d
  lp  <- newArray [castFunPtr fp0, castFunPtr fp1 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr mgr) lp nullPtr
  pure $ do
    freeHaskellFunPtr fp0
    freeHaskellFunPtr fp1
    free lp

----- input device

riverInputDeviceV1Destroy :: Ptr RiverInputDeviceV1 -> IO ()
riverInputDeviceV1Destroy = river_input_device_v1_destroy

foreign import capi "river-input-management-v1.h river_input_device_v1_destroy"
  river_input_device_v1_destroy :: Ptr RiverInputDeviceV1 -> IO ()

riverInputDeviceV1AssignToSeat :: Ptr RiverInputDeviceV1 -> String -> IO ()
riverInputDeviceV1AssignToSeat dev name =
  withCString name $ river_input_device_v1_assign_to_seat dev

foreign import capi "river-input-management-v1.h river_input_device_v1_assign_to_seat"
  river_input_device_v1_assign_to_seat :: Ptr RiverInputDeviceV1 -> CString -> IO ()

riverInputDeviceV1SetRepeatInfo :: Ptr RiverInputDeviceV1 -> Int -> Int -> IO ()
riverInputDeviceV1SetRepeatInfo dev rate delay =
  river_input_device_v1_set_repeat_info dev (fi rate) (fi delay)

foreign import capi "river-input-management-v1.h river_input_device_v1_set_repeat_info"
  river_input_device_v1_set_repeat_info :: Ptr RiverInputDeviceV1 -> CInt -> CInt -> IO ()

riverInputDeviceV1SetScrollFactor :: Ptr RiverInputDeviceV1 -> WlFixed -> IO ()
riverInputDeviceV1SetScrollFactor dev (WlFixed n) =
  river_input_device_v1_set_scroll_factor dev n

foreign import capi "river-input-management-v1.h river_input_device_v1_set_scroll_factor"
  river_input_device_v1_set_scroll_factor :: Ptr RiverInputDeviceV1 -> CInt -> IO ()

riverInputDeviceV1MapToOutput :: Ptr RiverInputDeviceV1 -> Ptr WlOutput -> IO ()
riverInputDeviceV1MapToOutput = river_input_device_v1_map_to_output

foreign import capi "river-input-management-v1.h river_input_device_v1_map_to_output"
  river_input_device_v1_map_to_output :: Ptr RiverInputDeviceV1 -> Ptr WlOutput -> IO ()

riverInputDeviceV1MapToRectangle :: Ptr RiverInputDeviceV1 -> Int -> Int -> Int -> Int -> IO ()
riverInputDeviceV1MapToRectangle dev x y w h =
  river_input_device_v1_map_to_rectangle dev (fi x) (fi y) (fi w) (fi h)

foreign import capi "river-input-management-v1.h river_input_device_v1_map_to_rectangle"
  river_input_device_v1_map_to_rectangle
    :: Ptr RiverInputDeviceV1 -> CInt -> CInt -> CInt -> CInt -> IO ()

type RawDevRemoved = Ptr () -> Ptr RiverInputDeviceV1 -> IO ()
type RawDevType    = Ptr () -> Ptr RiverInputDeviceV1 -> CUInt -> IO ()
type RawDevName    = Ptr () -> Ptr RiverInputDeviceV1 -> CString -> IO ()

foreign import ccall "wrapper" mkRawDevRemoved :: RawDevRemoved -> IO (FunPtr RawDevRemoved)
foreign import ccall "wrapper" mkRawDevType    :: RawDevType    -> IO (FunPtr RawDevType)
foreign import ccall "wrapper" mkRawDevName    :: RawDevName    -> IO (FunPtr RawDevName)

data InputDeviceListener = InputDeviceListener
  { onDevRemoved :: Ptr RiverInputDeviceV1 -> IO ()
  , onDevType    :: Ptr RiverInputDeviceV1 -> Word32 -> IO ()
  , onDevName    :: Ptr RiverInputDeviceV1 -> String -> IO ()
  }

riverInputDeviceV1AddListener
  :: Ptr RiverInputDeviceV1 -> InputDeviceListener -> IO (IO ())
riverInputDeviceV1AddListener dev InputDeviceListener{..} = do
  fp0 <- mkRawDevRemoved $ \_ d    -> onDevRemoved d
  fp1 <- mkRawDevType    $ \_ d t  -> onDevType d (fi t)
  fp2 <- mkRawDevName    $ \_ d cs -> peekCString cs >>= onDevName d
  lp  <- newArray [castFunPtr fp0, castFunPtr fp1, castFunPtr fp2 :: FunPtr (IO ())]
  _ <- wl_proxy_add_listener (castPtr dev) lp nullPtr
  pure $ do
    freeHaskellFunPtr fp0
    freeHaskellFunPtr fp1
    freeHaskellFunPtr fp2
    free lp
