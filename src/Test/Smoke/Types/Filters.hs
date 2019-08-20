module Test.Smoke.Types.Filters where

import Control.Monad.Catch.Pure (runCatchT)
import Data.Aeson
import Data.Aeson.Types (typeMismatch)
import qualified Data.Vector as Vector
import Test.Smoke.Paths
import Test.Smoke.Types.Base

data FixtureFilter =
  FixtureFilter Executable Args
  deriving (Eq, Show)

instance FromJSON FixtureFilter where
  parseJSON array@(Array args) = do
    command <- sequence $ parseJSON <$> args
    if Vector.null command
      then typeMismatch "filter" array
      else do
        eitherExecutable <- runCatchT (parseAbsOrRelFile (Vector.head command))
        case eitherExecutable of
          Left exception -> fail $ show exception
          Right executable ->
            return $
            FixtureFilter
              (ExecutableProgram executable)
              (Args (Vector.tail command))
  parseJSON (String script) =
    return $
    FixtureFilter
      (ExecutableScript (Shell (Vector.singleton "sh")) script)
      mempty
  parseJSON invalid = typeMismatch "filter" invalid

data Filtered a
  = Unfiltered a
  | Filtered a FixtureFilter
  deriving (Eq, Show)

unfiltered :: Filtered a -> a
unfiltered (Unfiltered value) = value
unfiltered (Filtered unfilteredValue _) = unfilteredValue
