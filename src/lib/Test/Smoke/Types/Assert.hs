{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE GADTs #-}

module Test.Smoke.Types.Assert where

import Data.Default (Default (..))
import Data.Vector (Vector)
import Test.Smoke.Types.Filters

data Assert a where
  AssertEqual :: Eq a => a -> Assert a
  AssertFiltered :: Filter -> Assert a -> Assert a

instance (Default a, Eq a) => Default (Assert a) where
  def = AssertEqual def

data AssertionFailure a
  = AssertionFailureDiff a a
  deriving (Functor)

data AssertionFailures a
  = SingleAssertionFailure (AssertionFailure a)
  | MultipleAssertionFailures (Vector (AssertionFailure a))
  deriving (Functor)
