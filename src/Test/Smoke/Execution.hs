{-# LANGUAGE LambdaCase #-}

module Test.Smoke.Execution
  ( runTests
  ) where

import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT(..), runExceptT, throwE, withExceptT)
import Data.Default
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import Path
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode(..))
import System.IO.Error (isPermissionError, tryIOError)
import System.Process.ListLike (cwd, proc)
import System.Process.Text (readCreateProcessWithExitCode)
import Test.Smoke.Errors
import Test.Smoke.Filters
import Test.Smoke.Types

type Execution = ExceptT SmokeExecutionError IO

type ActualOutputs = (Status, StdOut, StdErr)

runTests :: Plan -> IO Results
runTests (Plan suites) =
  forM suites $ \case
    SuitePlanError suiteName errorMessage ->
      return $ SuiteResultError suiteName errorMessage
    SuitePlan suiteName location testPlans -> do
      testResults <-
        forM testPlans $ \case
          Left (TestPlanError test errorMessage) ->
            return $ TestResult test $ TestError $ PlanningError errorMessage
          Right testPlan -> runTest testPlan
      return $ SuiteResult suiteName location testResults

runTest :: TestPlan -> IO TestResult
runTest testPlan =
  handleError (TestResult (planTest testPlan) . TestError . ExecutionError) <$>
  runExceptT (processOutput testPlan =<< executeTest testPlan)

executeTest :: TestPlan -> Execution ActualOutputs
executeTest (TestPlan _ workingDirectory executable (Args args) (StdIn processStdIn) _ _ _) = do
  let workingDirectoryFilePath =
        toFilePath $ unWorkingDirectory workingDirectory
  workingDirectoryExists <- liftIO $ doesDirectoryExist workingDirectoryFilePath
  unless workingDirectoryExists $
    throwE $ NonExistentWorkingDirectory workingDirectory
  let executableName = toFilePath $ unExecutable executable
  (exitCode, processStdOut, processStdErr) <-
    withExceptT (handleExecutionError executable) $
    ExceptT $
    tryIOError $
    readCreateProcessWithExitCode
      ((proc executableName args) {cwd = Just workingDirectoryFilePath})
      processStdIn
  return (convertExitCode exitCode, StdOut processStdOut, StdErr processStdErr)

processOutput :: TestPlan -> ActualOutputs -> Execution TestResult
processOutput testPlan@(TestPlan test _ _ _ _ expectedStatus expectedStdOuts expectedStdErrs) (actualStatus, actualStdOut, actualStdErr) = do
  filteredStatus <-
    withExceptT ExecutionFilterError $
    applyFiltersFromFixture (testStatus test) actualStatus
  filteredStdOut <-
    withExceptT ExecutionFilterError $
    ifEmpty actualStdOut <$>
    applyFiltersFromFixtures (testStdOut test) actualStdOut
  filteredStdErr <-
    withExceptT ExecutionFilterError $
    ifEmpty actualStdErr <$>
    applyFiltersFromFixtures (testStdErr test) actualStdErr
  let statusResult = result $ Vector.singleton (expectedStatus, filteredStatus)
  let stdOutResult =
        result $ Vector.zip (defaultIfEmpty expectedStdOuts) filteredStdOut
  let stdErrResult =
        result $ Vector.zip (defaultIfEmpty expectedStdErrs) filteredStdErr
  return $
    TestResult test $
    if statusResult == PartSuccess &&
       stdOutResult == PartSuccess && stdErrResult == PartSuccess
      then TestSuccess
      else TestFailure testPlan statusResult stdOutResult stdErrResult
  where
    result :: Eq a => Vector (a, a) -> PartResult a
    result comparison =
      if Vector.any (uncurry (==)) comparison
        then PartSuccess
        else PartFailure comparison

handleExecutionError :: Executable -> IOError -> SmokeExecutionError
handleExecutionError executable e =
  if isPermissionError e
    then NonExecutableCommand executable
    else CouldNotExecuteCommand executable (show e)

convertExitCode :: ExitCode -> Status
convertExitCode ExitSuccess = Status 0
convertExitCode (ExitFailure value) = Status value

ifEmpty :: a -> Vector a -> Vector a
ifEmpty x xs
  | Vector.null xs = Vector.singleton x
  | otherwise = xs

defaultIfEmpty :: Default a => Vector a -> Vector a
defaultIfEmpty = ifEmpty def
