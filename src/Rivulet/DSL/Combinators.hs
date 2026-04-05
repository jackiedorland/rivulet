module Rivulet.DSL.Combinators where

import           Rivulet.Types

class Combinable f a | f -> a where
  items :: f -> [a]

infixr 6 <+>
(<+>) :: (Combinable f a, Combinable g a) => f -> g -> [a]
x <+> y = items x ++ items y

class LayoutList a where
  toLayouts :: a -> [SomeLayout]

instance Layout l => LayoutList l where
  toLayouts l = [SomeLayout l]

instance {-# OVERLAPPING #-} LayoutList [SomeLayout] where
  toLayouts = id

instance {-# OVERLAPPING #-} Layout l => LayoutList [l] where
  toLayouts = map SomeLayout

(>>.) :: (LayoutList a, LayoutList b) => a -> b -> [SomeLayout]
a >>. b = toLayouts a ++ toLayouts b

infixl 3 >>.
