module Rivulet.DSL.Layout where

import Rivulet.Types

data Full
    = Full

data Tall
    = Tall

data Grid
    = Grid

instance Layout Full where
    propose _ monitor (Margins gap bw) windows =
        case windows of
            []      -> []
            (w : _) -> [fullRect w]
      where
        screen = workArea monitor
        shrink = 2 * gap + 2 * bw
        fullRect wId =
            ( wId
            , Rect
                (x screen + gap)
                (y screen + gap)
                (width screen - shrink)
                (height screen - shrink)
            )
    arrange _ monitor (Margins gap bw) windows =
        case windows of
            []                  -> []
            ((wId, (w, h)) : _) -> [placeAt wId w h]
      where
        screen = workArea monitor
        placeAt wId w h = (wId, Rect (x screen + gap) (y screen + gap) w h)

instance Layout Tall where
    propose _ monitor (Margins gap bw) windows =
        case windows of
            []               -> []
            [w]              -> [fullRect w]
            (master : stack) -> masterRect master : stackRects stack
      where
        screen = workArea monitor
        availX = x screen + gap
        availY = y screen + gap
        availW = width screen - 2 * gap - 2 * bw
        availH = height screen - 2 * gap - 2 * bw
        masterW = (availW - gap) `div` 2
        stackW = availW - masterW - gap
        stackX = availX + masterW + gap
        fullRect wId = (wId, Rect availX availY availW availH)
        masterRect wId = (wId, Rect availX availY masterW availH)
        stackRects ws =
            let n = length ws
                perH = (availH - (n - 1) * gap) `div` n
                place (i, wId) =
                    (wId, Rect stackX (availY + i * (perH + gap)) stackW perH)
             in zipWith (curry place) [0 ..] ws
    arrange _ monitor (Margins gap bw) windows =
        case windows of
            []               -> []
            [(wId, (w, h))]  -> [placeAt availX availY wId w h]
            (master : stack) -> placeMaster master : placeStack stack
      where
        screen = workArea monitor
        availX = x screen + gap
        availY = y screen + gap
        availW = width screen - 2 * gap - 2 * bw
        stackX = availX + (availW - gap) `div` 2 + gap
        placeAt px py wId w h = (wId, Rect px py w h)
        placeMaster (wId, (w, h)) = placeAt availX availY wId w h
        placeStack ws =
            let yPositions = scanl (\y (_, (_, h)) -> y + h + gap) availY ws
                place y (wId, (w, h)) = placeAt stackX y wId w h
             in zipWith place yPositions ws
