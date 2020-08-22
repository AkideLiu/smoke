module Test.Smoke.Assert (assertResult) where

import Control.Monad.Trans.Except (ExceptT (..), runExceptT, withExceptT)
import Data.Default
import Data.Map.Strict ((!))
import qualified Data.Map.Strict as Map
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import Test.Smoke.Filters
import Test.Smoke.Paths
import Test.Smoke.Types

type Asserting = ExceptT SmokeAssertionError IO

assertResult ::
  ResolvedPath Dir -> TestPlan -> ExecutionResult -> IO TestOutcome
assertResult _ _ ExecutionIgnored =
  return TestIgnored
assertResult _ _ (ExecutionFailed exception) =
  return $ TestError (ExecutionError exception)
assertResult location testPlan (ExecutionSucceeded actualOutputs) =
  either (TestError . AssertionError) id <$> runExceptT (processOutputs location testPlan actualOutputs)

processOutputs :: ResolvedPath Dir -> TestPlan -> ActualOutputs -> Asserting TestOutcome
processOutputs location testPlan@(TestPlan test _ fallbackShell _ _ _ expectedStatus expectedStdOuts expectedStdErrs expectedFiles _) (ActualOutputs actualStatus actualStdOut actualStdErr actualFiles) = do
  filteredStatus <-
    withExceptT AssertionFilterError $
      applyFiltersFromFixture fallbackShell (testStatus test) actualStatus
  filteredStdOut <-
    withExceptT AssertionFilterError $
      ifEmpty actualStdOut
        <$> applyFiltersFromFixtures fallbackShell (testStdOut test) actualStdOut
  filteredStdErr <-
    withExceptT AssertionFilterError $
      ifEmpty actualStdErr
        <$> applyFiltersFromFixtures fallbackShell (testStdErr test) actualStdErr
  let statusResult = assertAll $ Vector.singleton (expectedStatus, filteredStatus)
  let stdOutResult =
        assertAll $ Vector.zip (defaultIfEmpty expectedStdOuts) filteredStdOut
  let stdErrResult =
        assertAll $ Vector.zip (defaultIfEmpty expectedStdErrs) filteredStdErr
  fileResults <-
    Map.traverseWithKey
      ( \relativePath contents ->
          assertAll . Vector.zip contents
            <$> withExceptT
              AssertionFilterError
              ( applyFiltersFromFixtures
                  fallbackShell
                  (testFiles test ! relativePath)
                  (actualFiles ! (location </> relativePath))
              )
      )
      expectedFiles
  return $
    if isPartSuccess statusResult
      && isPartSuccess stdOutResult
      && isPartSuccess stdErrResult
      && all isPartSuccess (Map.elems fileResults)
      then TestSuccess
      else
        TestFailure
          testPlan
          statusResult
          stdOutResult
          stdErrResult
          fileResults
  where
    assertAll :: Eq a => Vector (Assert a, a) -> PartResult a
    assertAll comparisons =
      maybe PartSuccess PartFailure $ sequence (Vector.map (uncurry assert) comparisons)
    assert :: Assert a -> a -> Maybe (AssertFailure a)
    assert (AssertEqual expected) actual =
      if expected == actual
        then Nothing
        else Just $ AssertFailureDiff expected actual

ifEmpty :: a -> Vector a -> Vector a
ifEmpty x xs
  | Vector.null xs = Vector.singleton x
  | otherwise = xs

defaultIfEmpty :: Default a => Vector a -> Vector a
defaultIfEmpty = ifEmpty def
